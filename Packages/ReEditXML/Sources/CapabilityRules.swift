import Foundation
import ReEditCore

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// Conservative capability assignment (spec §6.7): a node advertises an edit
/// capability only when Phase 0 understands the construct completely. When in
/// doubt, read-only.
enum CapabilityRules {
    /// Child elements of clips that never affect timeline timing; their
    /// presence does not demote the parent.
    static let harmlessChildren: Set<String> = [
        "adjust-blend", "adjust-cinematic", "adjust-colorConform", "adjust-conform",
        "adjust-corners", "adjust-crop", "adjust-EQ", "adjust-humReduction",
        "adjust-loudness", "adjust-matchEQ", "adjust-noiseReduction", "adjust-panner",
        "adjust-rollingShutter", "adjust-stabilization", "adjust-transform",
        "adjust-volume", "adjust-360-transform", "analysis-marker",
        "audio-channel-source", "audio-role-source", "bookmark", "chapter-marker",
        "filter-audio", "filter-video", "filter-video-mask", "keyword", "marker",
        "metadata", "note", "param", "rating", "text", "text-style-def",
    ]

    /// Child elements that change timing semantics Phase 0 has not proved;
    /// their presence forces the parent to read-only and is reported.
    static let timingAffectingChildren: Set<String> = ["timeMap", "conform-rate"]

    /// Base capabilities per node kind, before demotions.
    static func baseCapabilities(
        for kind: NodeKind, element: XMLElement, resources: ResourceIndex
    ) -> NodeCapabilities {
        switch kind {
        case .assetClip:
            return NodeCapabilities(
                canDeleteRange: true, canTrimStart: true, canTrimEnd: true,
                canEditAudio: hasAudio(element: element, resources: resources),
                canEditTitle: false)
        case .clip:
            return NodeCapabilities(
                canDeleteRange: true, canTrimStart: true, canTrimEnd: true,
                canEditAudio: hasAudio(element: element, resources: resources),
                canEditTitle: false)
        case .gap:
            return NodeCapabilities(
                canDeleteRange: true, canTrimStart: true, canTrimEnd: true,
                canEditAudio: false, canEditTitle: false)
        case .title:
            return NodeCapabilities(
                canDeleteRange: true, canTrimStart: true, canTrimEnd: true,
                canEditAudio: false, canEditTitle: true)
        case .video:
            return NodeCapabilities(
                canDeleteRange: false, canTrimStart: true, canTrimEnd: true,
                canEditAudio: false, canEditTitle: false)
        case .audio:
            return NodeCapabilities(
                canDeleteRange: false, canTrimStart: true, canTrimEnd: true,
                canEditAudio: true, canEditTitle: false)
        case .sequence, .spine, .transition, .refClip, .syncClip, .mcClip, .audition,
            .unknown:
            return .readOnly
        }
    }

    /// Whether a clip element demonstrably carries audio: an audio role, an
    /// audio adjustment, an explicit audio component, or a referenced asset
    /// that declares audio.
    static func hasAudio(element: XMLElement, resources: ResourceIndex) -> Bool {
        if DOM.attribute("audioRole", of: element) != nil {
            return true
        }
        for child in DOM.childElements(of: element) {
            if child.name == "adjust-volume" || child.name == "audio"
                || child.name == "audio-channel-source"
            {
                return true
            }
        }
        if let ref = DOM.attribute("ref", of: element),
            let asset = resources.element(withID: ref),
            DOM.attribute("hasAudio", of: asset) == "1"
        {
            return true
        }
        return false
    }
}

/// Index of `<resources>` children by `id`.
struct ResourceIndex {
    private let byID: [String: XMLElement]

    init(root: XMLElement) {
        var index: [String: XMLElement] = [:]
        if let resources = DOM.firstDescendant(named: "resources", of: root) {
            for child in DOM.descendants(of: resources) {
                if let id = DOM.attribute("id", of: child) {
                    index[id] = child
                }
            }
        }
        self.byID = index
    }

    func element(withID id: String) -> XMLElement? {
        byID[id]
    }

    var identifiers: Set<String> {
        Set(byID.keys)
    }
}
