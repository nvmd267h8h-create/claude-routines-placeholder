import Foundation
import ReEditCore

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// Facts recorded from the raw bytes before XML parsing.
///
/// FoundationXML on Linux does not reliably surface DTD/prolog nodes, so the
/// writer re-emits the declaration and `<!DOCTYPE fcpxml>` from this scan
/// instead of trusting the DOM (ADR-0004).
struct PrologInfo: Sendable, Equatable {
    /// Exact `<?xml ...?>` text, when the source starts with one.
    let xmlDeclaration: String?
    /// Exact `<!DOCTYPE ...>` text, when present before the root element.
    let doctype: String?
    /// Whether the source's final byte is a newline.
    let endsWithNewline: Bool

    static func scan(_ data: Data) -> PrologInfo {
        let bytes = [UInt8](data.prefix(4096))
        var index = 0

        func skipWhitespace() {
            while index < bytes.count,
                bytes[index] == 0x20 || bytes[index] == 0x09 || bytes[index] == 0x0A
                    || bytes[index] == 0x0D
            {
                index += 1
            }
        }

        func matches(_ prefix: String) -> Bool {
            let prefixBytes = Array(prefix.utf8)
            guard index + prefixBytes.count <= bytes.count else { return false }
            return Array(bytes[index..<(index + prefixBytes.count)]) == prefixBytes
        }

        var declaration: String?
        if matches("<?xml") {
            let start = index
            while index + 1 < bytes.count {
                if bytes[index] == UInt8(ascii: "?"), bytes[index + 1] == UInt8(ascii: ">") {
                    index += 2
                    declaration = String(decoding: bytes[start..<index], as: UTF8.self)
                    break
                }
                index += 1
            }
        }

        skipWhitespace()

        var doctype: String?
        if matches("<!DOCTYPE") {
            let start = index
            while index < bytes.count {
                if bytes[index] == UInt8(ascii: ">") {
                    index += 1
                    doctype = String(decoding: bytes[start..<index], as: UTF8.self)
                    break
                }
                index += 1
            }
        }

        return PrologInfo(
            xmlDeclaration: declaration,
            doctype: doctype,
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

        // Strict well-formedness gate first: Linux FoundationXML's XMLDocument
        // silently *recovers* malformed XML (verified in CI), so a SAX parse —
        // strict on both platforms — decides well-formedness.
        let strictParser = XMLParser(data: data)
        strictParser.externalEntityResolvingPolicy = .never
        if !strictParser.parse() {
            let underlying = strictParser.parserError.map(String.init(describing:))
                ?? "unknown parser error"
            throw FCPXMLLoadError.malformedXML(
                path: input.documentPath,
                underlying: "line \(strictParser.lineNumber): \(underlying)",
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
