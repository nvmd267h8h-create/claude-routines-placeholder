import Foundation

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// Deterministic FCPXML serializer (ADR-0004).
///
/// Parsing uses Foundation's `XMLDocument`; serialization is ours, so output
/// bytes are identical on Linux (FoundationXML) and macOS (Darwin Foundation)
/// and fully under our control: prolog re-emitted from the raw-byte scan,
/// attributes in document order, FCP-style escaping, whitespace-only text
/// nodes verbatim, childless elements self-closed.
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
        write(node: document.root, into: &output)
        if document.prolog.endsWithNewline {
            output += "\n"
        }
        return Data(output.utf8)
    }

    private static func write(node: XMLNode, into output: inout String) {
        switch node.kind {
        case .element:
            guard let element = node as? XMLElement else { return }
            output += "<" + (element.name ?? "")
            for attribute in element.attributes ?? [] {
                let name = attribute.name ?? ""
                let value = attribute.stringValue ?? ""
                output += " " + name + "=\"" + escapeAttribute(value) + "\""
            }
            let children = element.children ?? []
            if children.isEmpty {
                output += "/>"
            } else {
                output += ">"
                for child in children {
                    write(node: child, into: &output)
                }
                output += "</" + (element.name ?? "") + ">"
            }
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
