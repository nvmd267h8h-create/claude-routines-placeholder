import Foundation
import ReEditCore

/// How the input was supplied on disk.
public enum FCPXMLSourceKind: Sendable, Equatable {
    /// A plain `.fcpxml` file.
    case file
    /// A `.fcpxmld` bundle; `innerDocumentName` is the document found inside.
    case bundle(innerDocumentName: String)
}

/// A resolved FCPXML input: the path the user named plus the actual XML
/// document to read.
public struct FCPXMLInput: Sendable {
    /// The path the user supplied (file or bundle directory).
    public let inputPath: String
    /// The XML document to parse (equal to `inputPath` for plain files).
    public let documentPath: String
    public let kind: FCPXMLSourceKind

    /// Resolves a user-supplied path into a readable FCPXML document
    /// (spec §6.2: accept both `.fcpxml` files and `.fcpxmld` bundles).
    public static func resolve(
        path: String, fileSystem: any FileSystemProviding
    ) throws(FCPXMLLoadError) -> FCPXMLInput {
        guard fileSystem.fileExists(atPath: path) else {
            throw FCPXMLLoadError.fileNotFound(
                path: path,
                guidance: "Check the export path from Final Cut Pro (File > Export XML).")
        }

        let lowercased = path.lowercased()
        if fileSystem.isDirectory(atPath: path) {
            guard lowercased.hasSuffix(".fcpxmld") else {
                throw FCPXMLLoadError.notAnFCPXMLInput(
                    path: path,
                    guidance:
                        "Supply a .fcpxml file or a .fcpxmld bundle exported by Final Cut Pro.")
            }
            let entries: [String]
            do {
                entries = try fileSystem.contentsOfDirectory(atPath: path)
            } catch {
                throw FCPXMLLoadError.unreadable(
                    path: path, underlying: String(describing: error),
                    guidance: "Check permissions on the bundle directory.")
            }
            // Final Cut writes Info.fcpxml inside .fcpxmld bundles; fall back to
            // a single top-level .fcpxml for tolerance.
            if entries.contains("Info.fcpxml") {
                return FCPXMLInput(
                    inputPath: path,
                    documentPath: path + "/Info.fcpxml",
                    kind: .bundle(innerDocumentName: "Info.fcpxml"))
            }
            let candidates = entries.filter { $0.lowercased().hasSuffix(".fcpxml") }.sorted()
            guard let inner = candidates.first, candidates.count == 1 else {
                throw FCPXMLLoadError.bundleMissingDocument(
                    bundlePath: path,
                    guidance: candidates.isEmpty
                        ? "Expected Info.fcpxml inside the bundle. Re-export from Final Cut Pro."
                        : "Bundle contains multiple .fcpxml candidates; expected exactly one.")
            }
            return FCPXMLInput(
                inputPath: path,
                documentPath: path + "/" + inner,
                kind: .bundle(innerDocumentName: inner))
        }

        guard lowercased.hasSuffix(".fcpxml") else {
            throw FCPXMLLoadError.notAnFCPXMLInput(
                path: path,
                guidance:
                    "Supply a .fcpxml file or a .fcpxmld bundle exported by Final Cut Pro.")
        }
        return FCPXMLInput(inputPath: path, documentPath: path, kind: .file)
    }
}
