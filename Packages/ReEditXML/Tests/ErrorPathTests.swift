import Foundation
import ReEditCore
import Testing

@testable import ReEditXML

@Suite("Typed load errors")
struct ErrorPathTests {
    private func load(_ relative: String) throws(FCPXMLLoadError) -> FCPXMLDocument {
        try FCPXMLDocument(path: FixtureLocator.fixturePath(relative))
    }

    @Test func missingFile() {
        do {
            _ = try load("invalid/does-not-exist.fcpxml")
            Issue.record("expected fileNotFound")
        } catch {
            guard case .fileNotFound(let path, let guidance) = error else {
                Issue.record("expected fileNotFound, got \(error)")
                return
            }
            #expect(path.hasSuffix("does-not-exist.fcpxml"))
            #expect(!guidance.isEmpty)
        }
    }

    @Test func wrongExtension() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("reedit-wrong-ext-\(UUID().uuidString).xml")
        try Data("<fcpxml version=\"1.11\"/>".utf8).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        do {
            _ = try FCPXMLDocument(path: path.path)
            Issue.record("expected notAnFCPXMLInput")
        } catch let error as FCPXMLLoadError {
            guard case .notAnFCPXMLInput = error else {
                Issue.record("expected notAnFCPXMLInput, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type \(error)")
        }
    }

    @Test func malformedXML() {
        do {
            _ = try load("invalid/e01-malformed.fcpxml")
            Issue.record("expected malformedXML")
        } catch {
            guard case .malformedXML(let path, let underlying, let guidance) = error else {
                Issue.record("expected malformedXML, got \(error)")
                return
            }
            #expect(path.hasSuffix("e01-malformed.fcpxml"))
            #expect(!underlying.isEmpty)
            #expect(!guidance.isEmpty)
        }
    }

    @Test func missingVersion() {
        do {
            _ = try load("invalid/e02-missing-version.fcpxml")
            Issue.record("expected missingVersionAttribute")
        } catch {
            guard case .missingVersionAttribute(let xmlPath, _) = error else {
                Issue.record("expected missingVersionAttribute, got \(error)")
                return
            }
            #expect(xmlPath == "/fcpxml")
        }
    }

    @Test func emptyBundle() {
        do {
            _ = try load("invalid/e05-empty-bundle.fcpxmld")
            Issue.record("expected bundleMissingDocument")
        } catch {
            guard case .bundleMissingDocument(let bundlePath, let guidance) = error else {
                Issue.record("expected bundleMissingDocument, got \(error)")
                return
            }
            #expect(bundlePath.hasSuffix("e05-empty-bundle.fcpxmld"))
            #expect(guidance.contains("Info.fcpxml"))
        }
    }

    @Test func wrongRootElement() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("reedit-wrong-root-\(UUID().uuidString).fcpxml")
        try Data("<?xml version=\"1.0\"?>\n<plist version=\"1.0\"/>\n".utf8).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        do {
            _ = try FCPXMLDocument(path: path.path)
            Issue.record("expected missingRootElement")
        } catch let error as FCPXMLLoadError {
            guard case .missingRootElement(_, let found, _) = error else {
                Issue.record("expected missingRootElement, got \(error)")
                return
            }
            #expect(found == "plist")
        } catch {
            Issue.record("unexpected error type \(error)")
        }
    }

    @Test func errorsDescribeThemselves() {
        // Every error description must be non-empty and carry its guidance.
        let samples: [FCPXMLLoadError] = [
            .fileNotFound(path: "/x", guidance: "g"),
            .notAnFCPXMLInput(path: "/x", guidance: "g"),
            .bundleMissingDocument(bundlePath: "/x", guidance: "g"),
            .unreadable(path: "/x", underlying: "u", guidance: "g"),
            .malformedXML(path: "/x", underlying: "u", guidance: "g"),
            .missingRootElement(path: "/x", found: "plist", guidance: "g"),
            .missingVersionAttribute(xmlPath: "/fcpxml", guidance: "g"),
            .missingRequiredAttribute(
                xmlPath: "/fcpxml", element: "sequence", attribute: "format", guidance: "g"),
            .invalidTimeValue(
                xmlPath: "/fcpxml", attribute: "duration", value: "1.5s", underlying: "u",
                guidance: "g"),
            .danglingResourceReference(xmlPath: "/fcpxml", ref: "r99", guidance: "g"),
            .outputWouldOverwriteSource(input: "/a", output: "/a", guidance: "g"),
        ]
        for sample in samples {
            #expect(sample.description.contains("g"))
            #expect(!sample.description.isEmpty)
        }
    }
}
