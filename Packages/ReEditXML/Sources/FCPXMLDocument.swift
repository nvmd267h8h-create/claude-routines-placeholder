import Foundation
import ReEditCore

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// Strict well-formedness checking shared by the loader and the canonicalizer.
///
/// Linux FoundationXML's `XMLDocument` silently *recovers* malformed XML and
/// its `XMLParser.parse()` can return true despite fatal errors (both verified
/// in CI), so well-formedness is decided by a SAX parse with a delegate that
/// captures every reported error.
enum StrictXML {
    /// Returns nil when well-formed, else a description of the first error.
    static func wellFormednessError(in data: Data) -> String? {
        let parser = XMLParser(data: data)
        parser.externalEntityResolvingPolicy = .never
        let sink = ParseErrorSink()
        parser.delegate = sink
        let parsed = parser.parse()
        if let error = sink.firstError ?? (parsed ? nil : parser.parserError) {
            return "line \(parser.lineNumber): \(String(describing: error))"
        }
        return parsed ? nil : "line \(parser.lineNumber): unknown parser error"
    }

    private final class ParseErrorSink: NSObject, XMLParserDelegate {
        var firstError: Error?

        func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
            if firstError == nil {
                firstError = parseError
            }
        }
    }
}

/// Facts recorded from the raw bytes before XML parsing.
///
/// FoundationXML on Linux does not reliably surface DTD/prolog nodes, so the
/// writer re-emits everything before the root element — declaration, comments,
/// processing instructions and `<!DOCTYPE fcpxml>` (including an internal
/// subset) — from this scan instead of trusting the DOM (ADR-0004).
struct PrologInfo: Sendable, Equatable {
    /// Whether the source starts with a UTF-8 byte order mark.
    let hasByteOrderMark: Bool
    /// Prolog constructs before the root element, verbatim and in order.
    let items: [String]
    /// Whether the source's final byte is a newline.
    let endsWithNewline: Bool

    /// Exact `<?xml ...?>` text, when present.
    var xmlDeclaration: String? {
        items.first { $0.hasPrefix("<?xml") }
    }

    /// Exact `<!DOCTYPE ...>` text, when present.
    var doctype: String? {
        items.first { $0.hasPrefix("<!DOCTYPE") }
    }

    static func scan(_ data: Data) -> PrologInfo {
        // 64 KiB covers any realistic prolog; the root element ends the scan.
        let bytes = [UInt8](data.prefix(65536))
        var index = 0

        var hasBOM = false
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            hasBOM = true
            index = 3
        }

        func matches(_ prefix: String) -> Bool {
            let prefixBytes = Array(prefix.utf8)
            guard index + prefixBytes.count <= bytes.count else { return false }
            return Array(bytes[index..<(index + prefixBytes.count)]) == prefixBytes
        }

        func capture(until terminator: String) -> String? {
            let terminatorBytes = Array(terminator.utf8)
            let start = index
            while index + terminatorBytes.count <= bytes.count {
                if Array(bytes[index..<(index + terminatorBytes.count)]) == terminatorBytes {
                    index += terminatorBytes.count
                    return String(decoding: bytes[start..<index], as: UTF8.self)
                }
                index += 1
            }
            index = start
            return nil
        }

        /// DOCTYPE ends at the first '>' outside an internal subset's [...].
        func captureDoctype() -> String? {
            let start = index
            var subsetDepth = 0
            while index < bytes.count {
                let byte = bytes[index]
                if byte == UInt8(ascii: "[") {
                    subsetDepth += 1
                } else if byte == UInt8(ascii: "]") {
                    subsetDepth = max(0, subsetDepth - 1)
                } else if byte == UInt8(ascii: ">"), subsetDepth == 0 {
                    index += 1
                    return String(decoding: bytes[start..<index], as: UTF8.self)
                }
                index += 1
            }
            index = start
            return nil
        }

        var items: [String] = []
        scanning: while index < bytes.count {
            // Skip whitespace between prolog constructs.
            while index < bytes.count,
                bytes[index] == 0x20 || bytes[index] == 0x09 || bytes[index] == 0x0A
                    || bytes[index] == 0x0D
            {
                index += 1
            }
            if matches("<!--") {
                guard let comment = capture(until: "-->") else { break scanning }
                items.append(comment)
            } else if matches("<!DOCTYPE") {
                guard let doctype = captureDoctype() else { break scanning }
                items.append(doctype)
            } else if matches("<?") {
                guard let instruction = capture(until: "?>") else { break scanning }
                items.append(instruction)
            } else {
                // Root element (or EOF): the prolog is over.
                break scanning
            }
        }

        return PrologInfo(
            hasByteOrderMark: hasBOM,
            items: items,
            endsWithNewline: data.last == 0x0A)
    }
}

/// A loaded FCPXML document: raw source bytes, prolog facts, the retained DOM
/// and verified root metadata.
///
/// Read-only enforcement (spec §6.2): the DOM is `internal`, exposed outside
/// the module only through value types; nothing in Phase 0 mutates it, and no
/// API writes back to the source path.
public final class FCPXMLDocument {
    /// The resolved input this document was loaded from.
    public let input: FCPXMLInput
    /// The exact bytes read from disk. Never modified.
    public let sourceData: Data
    /// SHA-256 of `sourceData`, lowercase hex.
    public let sourceFingerprint: String
    /// The source `version` attribute, verbatim. Never rewritten (spec §6.2).
    public let version: String

    let prolog: PrologInfo
    /// The retained source DOM. Internal: value-type snapshots only, beyond
    /// this module.
    let dom: XMLDocument
    /// The `<fcpxml>` root element.
    let root: XMLElement

    /// Loads and verifies an FCPXML document without mutating anything on disk.
    public init(
        contentsOf input: FCPXMLInput, fileSystem: any FileSystemProviding
    ) throws(FCPXMLLoadError) {
        self.input = input

        let data: Data
        do {
            data = try fileSystem.read(contentsOf: URL(fileURLWithPath: input.documentPath))
        } catch {
            throw FCPXMLLoadError.unreadable(
                path: input.documentPath,
                underlying: String(describing: error),
                guidance: "Check the file exists and is readable.")
        }
        self.sourceData = data
        self.sourceFingerprint = SHA256.hexDigest([UInt8](data))
        self.prolog = PrologInfo.scan(data)

        if let error = StrictXML.wellFormednessError(in: data) {
            throw FCPXMLLoadError.malformedXML(
                path: input.documentPath,
                underlying: error,
                guidance: "Re-export the project from Final Cut Pro; do not hand-edit XML.")
        }

        let document: XMLDocument
        do {
            // External entities are never resolved (the FCPXML DOCTYPE has no
            // external identifier). Whitespace preservation is best-effort:
            // Darwin drops whitespace-only text nodes regardless; the writer
            // owns formatting (ADR-0004).
            document = try XMLDocument(data: data, options: [.nodePreserveWhitespace])
        } catch {
            throw FCPXMLLoadError.malformedXML(
                path: input.documentPath,
                underlying: String(describing: error),
                guidance: "Re-export the project from Final Cut Pro; do not hand-edit XML.")
        }
        self.dom = document

        guard let rootElement = document.rootElement(), rootElement.name == "fcpxml" else {
            throw FCPXMLLoadError.missingRootElement(
                path: input.documentPath,
                found: document.rootElement()?.name,
                guidance: "Expected a Final Cut Pro FCPXML export.")
        }
        self.root = rootElement

        guard let versionAttribute = rootElement.attribute(forName: "version")?.stringValue,
            !versionAttribute.isEmpty
        else {
            throw FCPXMLLoadError.missingVersionAttribute(
                xmlPath: "/fcpxml",
                guidance:
                    "Final Cut Pro always writes a version; this file may be truncated or hand-edited.")
        }
        self.version = versionAttribute
    }

    /// Convenience: resolve and load a user-supplied path.
    public convenience init(
        path: String, fileSystem: any FileSystemProviding = LiveFileSystem()
    ) throws(FCPXMLLoadError) {
        let input = try FCPXMLInput.resolve(path: path, fileSystem: fileSystem)
        try self.init(contentsOf: input, fileSystem: fileSystem)
    }
}
