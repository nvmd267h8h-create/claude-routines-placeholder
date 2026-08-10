import Foundation
import ReEditCore

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// Result of a no-op roundtrip fidelity check (spec §6.1).
public struct RoundtripReport: Sendable {
    /// Tier 1: serialized output is byte-identical to the source. The CI gate
    /// for canonical-style synthetic fixtures.
    public let byteIdentical: Bool
    /// Tier 2: output re-parses to the same canonical (semantic) form as the
    /// source. The gate for real-world exports, where stylistic byte drift is
    /// tolerable but semantic drift is not.
    public let canonicallyIdentical: Bool
    /// Whether the output re-parsed as well-formed XML at all.
    public let outputWellFormed: Bool
    /// SHA-256 of the source bytes.
    public let sourceFingerprint: String
    /// SHA-256 of the output bytes.
    public let outputFingerprint: String
    /// Output size in bytes.
    public let outputByteCount: Int
}

/// Serializes a loaded document with zero intentional edits and reports
/// fidelity against the source.
public enum RoundtripVerifier {
    public static func verify(_ document: FCPXMLDocument) -> (
        output: Data, report: RoundtripReport
    ) {
        let output = FCPXMLWriter.serialize(document)
        let byteIdentical = output == document.sourceData

        let outputCanonical = XMLCanonicalizer.canonicalForm(of: output)
        let sourceCanonical = XMLCanonicalizer.canonicalForm(of: document.dom)
        let canonicallyIdentical = outputCanonical != nil && outputCanonical == sourceCanonical

        let report = RoundtripReport(
            byteIdentical: byteIdentical,
            canonicallyIdentical: canonicallyIdentical,
            outputWellFormed: outputCanonical != nil,
            sourceFingerprint: document.sourceFingerprint,
            outputFingerprint: SHA256.hexDigest([UInt8](output)),
            outputByteCount: output.count)
        return (output, report)
    }
}
