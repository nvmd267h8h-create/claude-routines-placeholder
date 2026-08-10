import Foundation

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// Deterministic slash paths into the source document, used in errors, graph
/// nodes and sidecar manifests.
///
/// Convention (docs/phase0-conventions.md): the root element is `/fcpxml`;
/// every descendant element appends `name[i]` where `i` counts same-named
/// element siblings in document order, e.g.
/// `/fcpxml/library[0]/event[0]/project[0]/sequence[0]/spine[0]/asset-clip[2]`.
enum XMLPath {
    /// The path of `element` within its document.
    static func path(of element: XMLElement) -> String {
        var components: [String] = []
        var current: XMLElement? = element
        while let node = current {
            guard let parent = node.parent as? XMLElement else {
                // Document root: no sibling index by convention.
                components.append("/" + (node.name ?? "?"))
                break
            }
            components.append("\(node.name ?? "?")[\(sameNameIndex(of: node, in: parent))]")
            current = parent
        }
        return components.reversed().joined(separator: "/")
    }

    /// Index of `element` among its same-named element siblings.
    private static func sameNameIndex(of element: XMLElement, in parent: XMLElement) -> Int {
        var index = 0
        for child in parent.children ?? [] {
            guard let childElement = child as? XMLElement else { continue }
            if childElement === element {
                return index
            }
            if childElement.name == element.name {
                index += 1
            }
        }
        return index
    }
}
