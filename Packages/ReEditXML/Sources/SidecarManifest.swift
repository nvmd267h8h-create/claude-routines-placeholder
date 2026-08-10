import Foundation
import ReEditCore

/// Maps stableIDs to XML locations for one generated output (spec §6.3).
///
/// The manifest travels *next to* generated files as
/// `<output>.reedit-manifest.json`; production XML itself is never annotated.
public struct SidecarManifest: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        public let stableID: String
        public let xmlPath: String
        public let elementName: String
    }

    /// SHA-256 of the source document these identities are bound to.
    public let sourceFingerprint: String
    public let fcpxmlVersion: String
    public let entries: [Entry]

    public init(graph: TimelineGraph, sourceFingerprint: String) {
        self.sourceFingerprint = sourceFingerprint
        self.fcpxmlVersion = graph.fcpxmlVersion
        var entries: [Entry] = []
        func walk(_ node: TimelineNode) {
            entries.append(
                Entry(
                    stableID: node.stableID, xmlPath: node.xmlPath,
                    elementName: node.kind.elementName))
            for child in node.children {
                walk(child)
            }
        }
        for node in graph.nodes {
            walk(node)
        }
        self.entries = entries
    }

    /// Standard sidecar path for an output file.
    public static func sidecarPath(forOutput outputPath: String) -> String {
        outputPath + ".reedit-manifest.json"
    }

    /// Serialises with the stable encoder and writes atomically.
    public func write(
        forOutput outputPath: String, fileSystem: any FileSystemProviding
    ) throws {
        let data = try StableJSON.encode(self)
        try fileSystem.write(
            data, to: URL(fileURLWithPath: Self.sidecarPath(forOutput: outputPath)))
    }
}
