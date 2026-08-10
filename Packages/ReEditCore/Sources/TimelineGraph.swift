/// The element category of a timeline node (spec §6.3).
///
/// Kinds listed here have Phase 0 parsing; `refClip`, `syncClip`, `mcClip` and
/// `audition` are recognised but read-only until each has a dedicated parser and
/// fixtures. Everything else is `unknown` and read-only.
public enum NodeKind: Hashable, Sendable {
    case sequence
    case spine
    case assetClip
    case clip
    case gap
    case title
    case transition
    case video
    case audio
    case refClip
    case syncClip
    case mcClip
    case audition
    case unknown(elementName: String)

    /// The FCPXML element name this kind was parsed from.
    public var elementName: String {
        switch self {
        case .sequence: return "sequence"
        case .spine: return "spine"
        case .assetClip: return "asset-clip"
        case .clip: return "clip"
        case .gap: return "gap"
        case .title: return "title"
        case .transition: return "transition"
        case .video: return "video"
        case .audio: return "audio"
        case .refClip: return "ref-clip"
        case .syncClip: return "sync-clip"
        case .mcClip: return "mc-clip"
        case .audition: return "audition"
        case .unknown(let elementName): return elementName
        }
    }

    /// Maps an FCPXML element name to a kind; unmatched names become `.unknown`.
    public init(elementName: String) {
        switch elementName {
        case "sequence": self = .sequence
        case "spine": self = .spine
        case "asset-clip": self = .assetClip
        case "clip": self = .clip
        case "gap": self = .gap
        case "title": self = .title
        case "transition": self = .transition
        case "video": self = .video
        case "audio": self = .audio
        case "ref-clip": self = .refClip
        case "sync-clip": self = .syncClip
        case "mc-clip": self = .mcClip
        case "audition": self = .audition
        default: self = .unknown(elementName: elementName)
        }
    }
}

extension NodeKind: Codable {
    // Encodes as the element name string for readable golden files.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(elementName: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(elementName)
    }
}

/// A construct Phase 0 recognises but does not support for editing, reported so
/// limitations stay visible (spec §6.7, §10.3).
public struct UnsupportedConstruct: Codable, Hashable, Sendable {
    /// Slash path into the source document, e.g.
    /// `/fcpxml/library/event[0]/project[0]/sequence[0]/spine[0]/ref-clip[0]`.
    public let xmlPath: String
    public let elementName: String
    public let reason: String

    public init(xmlPath: String, elementName: String, reason: String) {
        self.xmlPath = xmlPath
        self.elementName = elementName
        self.reason = reason
    }
}

/// One node of the normalised, read-only timeline graph.
///
/// Absolute times exist only in this graph, never in the retained XML; they are
/// 0-based on the sequence's local timeline (`projectStart` holds the
/// presentation timecode origin separately).
public struct TimelineNode: Codable, Hashable, Sendable {
    /// Deterministic identity derived from the source fingerprint, xmlPath and
    /// node fingerprint. Stored in sidecar data only — never injected into
    /// production XML.
    public let stableID: String
    public let xmlPath: String
    public let kind: NodeKind
    public let parentID: String?
    /// Storyline lane: 0 is the primary storyline; connected clips use the
    /// lanes above (positive) or below (negative) their anchor.
    public let lane: Int
    /// 0-based start on the sequence timeline.
    public let absoluteStart: FCPTime
    public let duration: FCPTime
    /// The clip's `start` attribute (media in-point), when present.
    public let sourceStart: FCPTime?
    /// The `ref` attribute resolving into `<resources>`, when present.
    public let resourceRef: String?
    /// Video or audio role, when present.
    public let role: String?
    public let capabilities: NodeCapabilities
    public let children: [TimelineNode]

    public init(
        stableID: String,
        xmlPath: String,
        kind: NodeKind,
        parentID: String?,
        lane: Int,
        absoluteStart: FCPTime,
        duration: FCPTime,
        sourceStart: FCPTime?,
        resourceRef: String?,
        role: String?,
        capabilities: NodeCapabilities,
        children: [TimelineNode]
    ) {
        self.stableID = stableID
        self.xmlPath = xmlPath
        self.kind = kind
        self.parentID = parentID
        self.lane = lane
        self.absoluteStart = absoluteStart
        self.duration = duration
        self.sourceStart = sourceStart
        self.resourceRef = resourceRef
        self.role = role
        self.capabilities = capabilities
        self.children = children
    }
}

/// The normalised, read-only timeline graph for one project (spec §6.3).
public struct TimelineGraph: Codable, Hashable, Sendable {
    /// stableID of the project element.
    public let projectID: String
    public let projectName: String
    /// Source document version, verbatim — never rewritten.
    public let fcpxmlVersion: String
    /// The sequence's `tcStart` (presentation timecode origin). Graph times are
    /// 0-based; consumers add `projectStart` for display timecode.
    public let projectStart: FCPTime
    public let duration: FCPTime
    /// One frame on the sequence's format, from `<format frameDuration=...>`.
    public let frameDuration: FCPTime
    /// Root nodes: the sequence's spine(s).
    public let nodes: [TimelineNode]
    /// Constructs recognised but not supported for editing, in document order.
    public let unsupported: [UnsupportedConstruct]

    public init(
        projectID: String,
        projectName: String,
        fcpxmlVersion: String,
        projectStart: FCPTime,
        duration: FCPTime,
        frameDuration: FCPTime,
        nodes: [TimelineNode],
        unsupported: [UnsupportedConstruct]
    ) {
        self.projectID = projectID
        self.projectName = projectName
        self.fcpxmlVersion = fcpxmlVersion
        self.projectStart = projectStart
        self.duration = duration
        self.frameDuration = frameDuration
        self.nodes = nodes
        self.unsupported = unsupported
    }
}
