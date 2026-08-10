import Foundation

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// Deterministic FCPXML serializer (ADR-0004).
///
/// Parsing uses Foundation's `XMLDocument`; serialization is ours. The writer
/// owns formatting entirely: Darwin Foundation drops whitespace-only text
/// nodes even with `.nodePreserveWhitespace` (verified in CI), so instead of
/// trusting the DOM for whitespace the writer emits Final Cut's canonical
/// style itself — four-space indentation, one element per line, childless
/// elements self-closed, attributes in document order, FCP-style escaping.
/// Mixed content (elements with significant text, e.g. `<text>`) is emitted
/// inline with no injected whitespace, because whitespace there is meaning.
///
/// Sources already in canonical style (all synthetic fixtures, normal Final
/// Cut exports) therefore roundtrip byte-identically on both platforms; other
/// formatting styles roundtrip to canonical form and are covered by the
/// canonical comparison tier.
enum FCPXMLWriter {
    /// Serializes the document's retained DOM back to bytes.
    static func serialize(_ document: FCPXMLDocument) -> Data {
        var output = ""
        if let declaration = document.prolog.xmlDeclaration {
            output += declaration + "\n"
        }
        if let doctype = document.prolog.doctype {
            output += doctype + "\n"
        }
        write(node: document.root, depth: 0, inline: false, into: &output)
        if document.prolog.endsWithNewline {
            output += "\n"
        }
        return Data(output.utf8)
    }

    private static func write(
        node: XMLNode, depth: Int, inline: Bool, into output: inout String
    ) {
        switch node.kind {
        case .element:
            guard let element = node as? XMLElement else { return }
            output += "<" + (element.name ?? "")
            for attribute in element.attributes ?? [] {
                let name = attribute.name ?? ""
                let value = attribute.stringValue ?? ""
                output += " " + name + "=\"" + escapeAttribute(value) + "\""
            }
            // Whitespace-only text nodes are formatting, not content; the
            // writer re-derives formatting itself (see type comment).
            let children = (element.children ?? []).filter { !isIgnorableWhitespace($0) }
            if children.isEmpty {
                output += "/>"
                return
            }
            output += ">"
            let hasSignificantText = children.contains { child in
                child.kind == .text
            }
            if inline || hasSignificantText {
                for child in children {
                    write(node: child, depth: depth + 1, inline: true, into: &output)
                }
            } else {
                let childIndent = String(repeating: "    ", count: depth + 1)
                for child in children {
                    output += "\n" + childIndent
                    write(node: child, depth: depth + 1, inline: false, into: &output)
                }
                output += "\n" + String(repeating: "    ", count: depth)
            }
            output += "</" + (element.name ?? "") + ">"
        case .text:
            output += escapeText(node.stringValue ?? "")
        case .comment:
            output += "<!--" + (node.stringValue ?? "") + "-->"
        case .processingInstruction:
            let name = node.name ?? ""
            let value = node.stringValue ?? ""
            output += value.isEmpty ? "<?\(name)?>" : "<?\(name) \(value)?>"
        default:
            // DTD internals and namespace nodes never occur below an FCPXML
            // root; anything unexpected is skipped rather than invented.
            break
        }
    }

    /// Whitespace-only text nodes between elements carry formatting only.
    private static func isIgnorableWhitespace(_ node: XMLNode) -> Bool {
        guard node.kind == .text else { return false }
        let text = node.stringValue ?? ""
        return !text.isEmpty
            && text.allSatisfy { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }
    }

    /// Escaping for text content: `&`, `<`, `>` only, matching FCP output.
    static func escapeText(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    /// Escaping for attribute values: XML specials plus numeric references for
    /// newline/tab/CR, which Final Cut uses inside title text attributes and
    /// which must survive a roundtrip byte-exactly.
    static func escapeAttribute(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "\n": escaped += "&#10;"
            case "\t": escaped += "&#9;"
            case "\r": escaped += "&#13;"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}
