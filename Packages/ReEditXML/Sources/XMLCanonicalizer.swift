import Foundation

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// Produces a semantic-comparison form of a document: attributes sorted by
/// name, whitespace-only text nodes and comments dropped, remaining text kept
/// verbatim. Inside mixed content (`<text>` subtrees) whitespace-only text IS
/// meaning and is kept.
///
/// Two documents with equal canonical forms carry the same FCPXML meaning even
/// when quoting style, attribute order or indentation differ — the comparison
/// tier used for real-world exports, where the byte tier is too strict
/// (ADR-0004).
enum XMLCanonicalizer {
    /// Canonical form of a parsed document.
    static func canonicalForm(of document: XMLDocument) -> String {
        guard let root = document.rootElement() else { return "" }
        var output = ""
        appendCanonical(node: root, depth: 0, inMixedContent: false, into: &output)
        return output
    }

    /// Parses `data` and returns its canonical form, or nil when not
    /// strictly well-formed (the recovering DOM parse is never the authority —
    /// see StrictXML).
    static func canonicalForm(of data: Data) -> String? {
        guard StrictXML.wellFormednessError(in: data) == nil,
            let document = try? XMLDocument(data: data, options: [.nodePreserveWhitespace])
        else {
            return nil
        }
        return canonicalForm(of: document)
    }

    private static func appendCanonical(
        node: XMLNode, depth: Int, inMixedContent: Bool, into output: inout String
    ) {
        let indent = String(repeating: " ", count: depth)
        switch node.kind {
        case .element:
            guard let element = node as? XMLElement else { return }
            let attributes = (element.attributes ?? [])
                .map { (name: $0.name ?? "", value: $0.stringValue ?? "") }
                .sorted { $0.name < $1.name }
                .map { "\($0.name)=\u{22}\($0.value)\u{22}" }
                .joined(separator: " ")
            output += indent + "(" + (element.name ?? "")
            if !attributes.isEmpty {
                output += " " + attributes
            }
            output += "\n"
            let mixed =
                inMixedContent
                || FCPXMLWriter.mixedContentElements.contains(element.name ?? "")
            for child in element.children ?? [] {
                appendCanonical(node: child, depth: depth + 1, inMixedContent: mixed, into: &output)
            }
            output += indent + ")\n"
        case .text:
            let text = node.stringValue ?? ""
            let isWhitespaceOnly = text.allSatisfy {
                $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r"
            }
            // Whitespace-only text is formatting outside mixed content, but
            // meaning inside it (a space-only styled title run).
            if !isWhitespaceOnly || inMixedContent {
                output += indent + "text:" + text + "\n"
            }
        default:
            // Comments and processing instructions carry no FCPXML semantics.
            break
        }
    }
}
