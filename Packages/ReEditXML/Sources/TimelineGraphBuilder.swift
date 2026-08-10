import Foundation
import ReEditCore

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// Builds the normalised, read-only timeline graph (spec §6.3) from a loaded
/// document. Absolute times exist only here; the retained DOM keeps its local
/// offsets untouched.
public enum TimelineGraphBuilder {
    public static func build(
        from document: FCPXMLDocument
    ) throws(FCPXMLLoadError) -> TimelineGraph {
        let root = document.root
        let resources = ResourceIndex(root: root)

        let projects = DOM.descendants(of: root).filter { $0.name == "project" }
        guard let project = projects.first else {
            throw FCPXMLLoadError.missingRequiredAttribute(
                xmlPath: "/fcpxml", element: "fcpxml", attribute: "project",
                guidance: "The document contains no <project>. Export a project, not a bare event.")
        }
        guard let sequence = DOM.firstDescendant(named: "sequence", of: project) else {
            throw FCPXMLLoadError.missingRequiredAttribute(
                xmlPath: XMLPath.path(of: project), element: "project", attribute: "sequence",
                guidance: "The project has no <sequence>; the export may be incomplete.")
        }

        let frameInfo = try SequenceTiming.frameDuration(for: sequence, in: root)
        let projectStart = try SequenceTiming.time(
            attribute: "tcStart", of: sequence, default: .zero)
        let declaredDuration = try SequenceTiming.time(
            attribute: "duration", of: sequence, default: .zero)

        var builder = Builder(
            document: document, resources: resources, frameDuration: frameInfo.value)
        var spineNodes: [TimelineNode] = []
        for child in DOM.childElements(of: sequence) where child.name == "spine" {
            spineNodes.append(
                try builder.buildNode(
                    element: child, parentID: nil, parentAbsoluteStart: .zero,
                    parentSourceStart: .zero, parentDuration: declaredDuration))
        }

        return TimelineGraph(
            projectID: builder.stableID(for: project),
            projectName: DOM.attribute("name", of: project) ?? "(unnamed)",
            fcpxmlVersion: document.version,
            projectStart: projectStart,
            duration: declaredDuration,
            frameDuration: frameInfo.value,
            nodes: spineNodes,
            unsupported: builder.unsupported)
    }

    /// Mutable build state: collects unsupported constructs while recursing.
    private struct Builder {
        let document: FCPXMLDocument
        let resources: ResourceIndex
        let frameDuration: FCPTime
        var unsupported: [UnsupportedConstruct] = []

        func stableID(for element: XMLElement) -> String {
            let attributes = (element.attributes ?? []).map {
                (name: $0.name ?? "", value: $0.stringValue ?? "")
            }
            return StableID.derive(
                sourceFingerprint: document.sourceFingerprint,
                xmlPath: XMLPath.path(of: element),
                nodeFingerprint: StableID.nodeFingerprint(
                    elementName: element.name ?? "", attributes: attributes))
        }

        /// Recursively builds one timeline node.
        ///
        /// Absolute time recursion: a child's `offset` is expressed on its
        /// parent's local timeline, whose origin sits at the parent's `start`
        /// (media in-point), so:
        /// `absStart(child) = absStart(parent) + (child.offset - parent.start)`.
        mutating func buildNode(
            element: XMLElement,
            parentID: String?,
            parentAbsoluteStart: FCPTime,
            parentSourceStart: FCPTime,
            parentDuration: FCPTime
        ) throws(FCPXMLLoadError) -> TimelineNode {
            let kind = NodeKind(elementName: element.name ?? "?")
            let xmlPath = XMLPath.path(of: element)
            let id = stableID(for: element)

            let offset = try SequenceTiming.time(attribute: "offset", of: element, default: .zero)
            let sourceStartAttribute = DOM.attribute("start", of: element)
            let sourceStart = try SequenceTiming.time(
                attribute: "start", of: element, default: .zero)
            // Components without their own duration span their parent.
            let defaultDuration = (kind == .video || kind == .audio) ? parentDuration : .zero
            let duration = try SequenceTiming.time(
                attribute: "duration", of: element, default: defaultDuration)

            let absoluteStart: FCPTime
            do {
                absoluteStart = try parentAbsoluteStart.adding(
                    offset.subtracting(parentSourceStart))
            } catch {
                throw FCPXMLLoadError.invalidTimeValue(
                    xmlPath: xmlPath, attribute: "offset", value: offset.fcpxmlString,
                    underlying: error.description,
                    guidance: "Timeline positions overflowed exact arithmetic; the file is suspect.")
            }

            let lane = Int(DOM.attribute("lane", of: element) ?? "0") ?? 0
            let role =
                DOM.attribute("role", of: element)
                ?? DOM.attribute("audioRole", of: element)
                ?? DOM.attribute("videoRole", of: element)

            var capabilities = CapabilityRules.baseCapabilities(
                for: kind, element: element, resources: resources)

            // Recognised-but-unproven containers are reported once, and their
            // internals are not traversed (spec §3.3).
            switch kind {
            case .refClip, .syncClip, .mcClip, .audition:
                unsupported.append(
                    UnsupportedConstruct(
                        xmlPath: xmlPath, elementName: kind.elementName,
                        reason:
                            "\(kind.elementName) requires a dedicated parser and fixtures before editing (read-only)."))
                return TimelineNode(
                    stableID: id, xmlPath: xmlPath, kind: kind, parentID: parentID,
                    lane: lane, absoluteStart: absoluteStart, duration: duration,
                    sourceStart: sourceStartAttribute == nil ? nil : sourceStart,
                    resourceRef: DOM.attribute("ref", of: element), role: role,
                    capabilities: .readOnly, children: [])
            default:
                break
            }

            var children: [TimelineNode] = []
            for child in DOM.childElements(of: element) {
                let childName = child.name ?? "?"
                if CapabilityRules.harmlessChildren.contains(childName) {
                    continue
                }
                if CapabilityRules.timingAffectingChildren.contains(childName) {
                    capabilities = .readOnly
                    unsupported.append(
                        UnsupportedConstruct(
                            xmlPath: XMLPath.path(of: child), elementName: childName,
                            reason:
                                "\(childName) retimes its parent; the construct is preserved but read-only."))
                    continue
                }
                let childKind = NodeKind(elementName: childName)
                if case .unknown = childKind {
                    // Unknown structural child: parent goes read-only, child is
                    // reported and represented without timing claims.
                    capabilities = .readOnly
                    unsupported.append(
                        UnsupportedConstruct(
                            xmlPath: XMLPath.path(of: child), elementName: childName,
                            reason:
                                "Unknown element; preserved in output but not editable (read-only)."))
                }
                children.append(
                    try buildNode(
                        element: child, parentID: id,
                        parentAbsoluteStart: absoluteStart,
                        parentSourceStart: sourceStart,
                        parentDuration: duration))
            }

            return TimelineNode(
                stableID: id, xmlPath: xmlPath, kind: kind, parentID: parentID,
                lane: lane, absoluteStart: absoluteStart, duration: duration,
                sourceStart: sourceStartAttribute == nil ? nil : sourceStart,
                resourceRef: DOM.attribute("ref", of: element), role: role,
                capabilities: capabilities, children: children)
        }
    }
}

/// Stable JSON encoding shared by graph output and sidecar manifests: sorted
/// keys, pretty printed, no slash escaping. Structural equality is the primary
/// golden gate; byte equality is asserted on Linux only (Foundation formatting
/// may differ across platforms).
public enum StableJSON {
    public static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
