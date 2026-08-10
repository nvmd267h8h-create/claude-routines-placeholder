import Foundation

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// Small read-only DOM traversal helpers shared by inspector, validator and
/// graph builder.
enum DOM {
    /// Element children of `element`, in document order.
    static func childElements(of element: XMLElement) -> [XMLElement] {
        (element.children ?? []).compactMap { $0 as? XMLElement }
    }

    /// Depth-first search for the first descendant element with `name`.
    static func firstDescendant(named name: String, of element: XMLElement) -> XMLElement? {
        for child in childElements(of: element) {
            if child.name == name {
                return child
            }
            if let found = firstDescendant(named: name, of: child) {
                return found
            }
        }
        return nil
    }

    /// All descendant elements (excluding `element` itself), document order.
    static func descendants(of element: XMLElement) -> [XMLElement] {
        var result: [XMLElement] = []
        for child in childElements(of: element) {
            result.append(child)
            result.append(contentsOf: descendants(of: child))
        }
        return result
    }

    /// Attribute value, if present.
    static func attribute(_ name: String, of element: XMLElement) -> String? {
        element.attribute(forName: name)?.stringValue
    }
}
