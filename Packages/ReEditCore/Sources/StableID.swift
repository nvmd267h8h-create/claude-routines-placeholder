/// Deterministic node identity (spec §6.3).
///
/// A stableID binds a graph node to one source revision: it hashes the source
/// document fingerprint, the node's xmlPath and the node's own content
/// fingerprint. IDs live in graph JSON and sidecar manifests only — production
/// XML is never annotated.
public enum StableID {
    /// Unit separator keeps the three components unambiguous in the hash input.
    private static let separator = "\u{1F}"

    /// 32-hex-character identity for a node of a specific source document.
    public static func derive(
        sourceFingerprint: String,
        xmlPath: String,
        nodeFingerprint: String
    ) -> String {
        let combined =
            sourceFingerprint + separator + xmlPath + separator + nodeFingerprint
        return String(SHA256.hexDigest(of: combined).prefix(32))
    }

    /// Content fingerprint of a node: element name plus its attributes sorted
    /// by name, so attribute order in the source never changes identity.
    public static func nodeFingerprint(
        elementName: String,
        attributes: [(name: String, value: String)]
    ) -> String {
        let sorted = attributes.sorted { $0.name < $1.name }
        let payload =
            elementName + separator
            + sorted.map { "\($0.name)=\($0.value)" }.joined(separator: separator)
        return SHA256.hexDigest(of: payload)
    }
}
