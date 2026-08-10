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
///
/// Mixed content is where whitespace is meaning, so it is never reformatted:
/// inside `<text>` (title content) and inside any element with significant
/// text, every child — including whitespace-only text runs — is emitted
/// verbatim inline. (Darwin's parser may have already dropped whitespace-only
/// runs before the writer sees them; that platform limitation is recorded in
/// ADR-0004 and checked at the Final Cut import gate.)
///
/// Sources already in canonical style (all synthetic fixtures, normal Final
/// Cut exports) therefore roundtrip byte-identically; other formatting styles
/// roundtrip to canonical form and are covered by the canonical comparison
/// tier.
enum FCPXMLWriter {
    /// Element names whose subtree is mixed content: children are emitted
    /// inline and whitespace-only text is preserved, never filtered.
    static let mixedContentElements: Set<String> = ["text"]

    /// Serializes the document's retained DOM back to bytes.
    static func serialize(_ document: FCPXMLDocument) -> Data {
        var output = ""
        if document.prolog.hasByteOrderMark {
            output += "\u{FEFF}"
        }
        for item in document.prolog.items {
            output += item + "\n"
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
            let allChildren = element.children ?? []
            let significantChildren = allChildren.filter { !isIgnorableWhitespace($0) }
            let inlineMode =
                inline
                || mixedContentElements.contains(element.name ?? "")
                || significantChildren.contains { $0.kind == .text }

            if inlineMode {
                if allChildren.isEmpty {
                    output += "/>"
                    return
                }
                output += ">"
                for child in allChildren {
                    write(node: child, depth: depth + 1, inline: true, into: &output)
                }
            } else {
                // Whitespace-only text between structural elements is
                // formatting; the writer re-derives it (see type comment).
                if significantChildren.isEmpty {
                    output += "/>"
                    return
                }
                output += ">"
                let childIndent = String(repeating: "    ", count: depth + 1)
                for child in significantChildren {
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

    /// Whitespace-only text nodes between structural elements carry
    /// formatting only. (Never applied inside mixed content.)
    private static func isIgnorableWhitespace(_ node: XMLNode) -> Bool {
        guard node.kind == .text else { return false }
        let text = node.stringValue ?? ""
        return !text.isEmpty
            && text.allSatisfy { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }
    }

    /// Escaping for text content: `&`, `<`, `>` plus a numeric reference for
    /// CR (which bare would be normalised to LF by any XML reparse).
    static func escapeText(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\r": escaped += "&#13;"
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
