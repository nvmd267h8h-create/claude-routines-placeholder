import Foundation
import ReEditCore
import ReEditXML

/// Exit codes fixed by docs/phase0-conventions.md.
enum ExitCode {
    static let success: Int32 = 0
    static let findings: Int32 = 1
    static let usage: Int32 = 2
    static let loadError: Int32 = 3
    static let internalError: Int32 = 4
}

/// Command implementations. Human output goes to stdout, diagnostics to
/// stderr; every path returns an explicit exit code.
enum Commands {
    static func run(_ command: ParsedCommand, fileSystem: any FileSystemProviding) -> Int32 {
        do {
            switch command {
            case .help:
                print(CLIArguments.usage)
                return ExitCode.success
            case .version:
                print("reedit \(ReEditCoreInfo.version)")
                return ExitCode.success
            case .inspect(let input):
                return try inspect(input: input, fileSystem: fileSystem)
            case .validate(let input):
                return try validate(input: input, fileSystem: fileSystem)
            case .roundtrip(let input, let output):
                return try roundtrip(input: input, output: output, fileSystem: fileSystem)
            case .graph(let input, let json):
                return try graph(input: input, json: json, fileSystem: fileSystem)
            }
        } catch let error as FCPXMLLoadError {
            FileHandle.standardError.write(Data((error.description + "\n").utf8))
            return ExitCode.loadError
        } catch {
            FileHandle.standardError.write(
                Data("Internal error: \(error)\n".utf8))
            return ExitCode.internalError
        }
    }

    private static func inspect(
        input: String, fileSystem: any FileSystemProviding
    ) throws -> Int32 {
        let document = try FCPXMLDocument(path: input, fileSystem: fileSystem)
        let report = try Inspector.inspect(document)
        print(report.renderedText, terminator: "")
        return ExitCode.success
    }

    private static func validate(
        input: String, fileSystem: any FileSystemProviding
    ) throws -> Int32 {
        let document = try FCPXMLDocument(path: input, fileSystem: fileSystem)
        let report = Validator.validate(document)
        print(report.renderedText, terminator: "")
        return report.hasErrors ? ExitCode.findings : ExitCode.success
    }

    /// Never write over a source (spec §1.5). Fail-closed: symlinks are
    /// resolved, comparison is case-insensitive (macOS filesystems usually
    /// are), containment covers outputs inside a .fcpxmld bundle input, and
    /// when the output already exists its file identity is compared too.
    private static func ensureOutputDoesNotTouchSource(
        input: String, output: String
    ) throws {
        let inputPath = URL(fileURLWithPath: input).standardizedFileURL
            .resolvingSymlinksInPath().path
        let outputPath = URL(fileURLWithPath: output).standardizedFileURL
            .resolvingSymlinksInPath().path
        let lowerInput = inputPath.lowercased()
        let lowerOutput = outputPath.lowercased()
        var collides = lowerOutput == lowerInput || lowerOutput.hasPrefix(lowerInput + "/")

        if !collides, FileManager.default.fileExists(atPath: outputPath),
            let inputAttributes = try? FileManager.default.attributesOfItem(atPath: inputPath),
            let outputAttributes = try? FileManager.default.attributesOfItem(atPath: outputPath),
            let inputInode = inputAttributes[.systemFileNumber] as? UInt64,
            let outputInode = outputAttributes[.systemFileNumber] as? UInt64,
            inputInode == outputInode
        {
            collides = true
        }

        if collides {
            throw FCPXMLLoadError.outputWouldOverwriteSource(
                input: inputPath, output: outputPath,
                guidance: "Choose an output path outside the source input.")
        }
    }

    private static func roundtrip(
        input: String, output: String, fileSystem: any FileSystemProviding
    ) throws -> Int32 {
        try ensureOutputDoesNotTouchSource(input: input, output: output)
        if output.lowercased().hasSuffix(".fcpxmld") {
            throw FCPXMLLoadError.notAnFCPXMLInput(
                path: output,
                guidance:
                    "Roundtrip writes a flat FCPXML document; choose a .fcpxml output path.")
        }
        let outputURL = URL(fileURLWithPath: output).standardizedFileURL

        let document = try FCPXMLDocument(path: input, fileSystem: fileSystem)
        let (outputData, report) = RoundtripVerifier.verify(document)
        try fileSystem.write(outputData, to: outputURL)

        print("Roundtrip written: \(outputURL.path)")
        print("Byte identical: \(report.byteIdentical ? "yes" : "no")")
        print("Canonically identical: \(report.canonicallyIdentical ? "yes" : "no")")
        print("Source fingerprint: \(report.sourceFingerprint)")
        print("Output fingerprint: \(report.outputFingerprint)")

        // The sidecar manifest binds stableIDs to this output; graph failures
        // (e.g. a resource-only document) degrade to a warning, not data loss.
        do {
            let graph = try TimelineGraphBuilder.build(from: document)
            let manifest = SidecarManifest(
                graph: graph, sourceFingerprint: document.sourceFingerprint)
            try manifest.write(forOutput: outputURL.path, fileSystem: fileSystem)
            print("Sidecar manifest: \(SidecarManifest.sidecarPath(forOutput: outputURL.path))")
            if !graph.unsupported.isEmpty {
                print("Unsupported constructs (read-only, preserved):")
                for construct in graph.unsupported {
                    print("  \(construct.xmlPath) <\(construct.elementName)>: \(construct.reason)")
                }
            }
        } catch let error as FCPXMLLoadError {
            FileHandle.standardError.write(
                Data("No sidecar manifest (graph unavailable): \(error.description)\n".utf8))
        }

        return report.canonicallyIdentical ? ExitCode.success : ExitCode.findings
    }

    private static func graph(
        input: String, json: String, fileSystem: any FileSystemProviding
    ) throws -> Int32 {
        try ensureOutputDoesNotTouchSource(input: input, output: json)
        let document = try FCPXMLDocument(path: input, fileSystem: fileSystem)
        let graph = try TimelineGraphBuilder.build(from: document)
        let data = try StableJSON.encode(graph)
        try fileSystem.write(data, to: URL(fileURLWithPath: json).standardizedFileURL)

        var nodeCount = 0
        func count(_ node: TimelineNode) {
            nodeCount += 1
            node.children.forEach(count)
        }
        graph.nodes.forEach(count)
        print(
            "Graph: \(nodeCount) nodes, \(graph.unsupported.count) unsupported → \(json)")
        return ExitCode.success
    }
}
