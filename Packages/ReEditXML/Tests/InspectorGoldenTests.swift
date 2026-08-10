import Foundation
import ReEditCore
import Testing

@testable import ReEditXML

@Suite("Inspector")
struct InspectorGoldenTests {
    @Test func f01ReportFields() throws {
        let document = try FCPXMLDocument(
            path: FixtureLocator.fixturePath("valid/f01-simple-25fps.fcpxml"))
        let report = try Inspector.inspect(document)
        #expect(report.fcpxmlVersion == "1.11")
        #expect(report.projectName == "Smith Wedding Highlights")
        #expect(report.projectCount == 1)
        #expect(report.frameDurationSource == "100/2500s")
        #expect(report.frameDuration == (try FCPTime(fcpxmlString: "1/25s")))
        #expect(report.framesPerSecondDisplay == "25")
        #expect(report.projectStart == FCPTime(seconds: 3600))
        #expect(report.duration == FCPTime(seconds: 18))
        #expect(report.nodeCounts["asset-clip"] == 3)
        #expect(report.nodeCounts["fcpxml"] == 1)
    }

    @Test func ntscFpsDisplay() throws {
        // Display formatting only — never edit logic (spec §5.3).
        let ntsc = InspectionReport(
            fcpxmlVersion: "1.11", projectName: "x", projectCount: 1,
            frameDurationSource: "1001/30000s",
            frameDuration: try FCPTime(fcpxmlString: "1001/30000s"),
            projectStart: .zero, duration: .zero, nodeCounts: [:])
        #expect(ntsc.framesPerSecondDisplay == "29.97")

        let cinema = InspectionReport(
            fcpxmlVersion: "1.11", projectName: "x", projectCount: 1,
            frameDurationSource: "1001/24000s",
            frameDuration: try FCPTime(fcpxmlString: "1001/24000s"),
            projectStart: .zero, duration: .zero, nodeCounts: [:])
        #expect(cinema.framesPerSecondDisplay == "23.98")
    }

    @Test func renderedTextMatchesGolden() throws {
        let document = try FCPXMLDocument(
            path: FixtureLocator.fixturePath("valid/f01-simple-25fps.fcpxml"))
        let report = try Inspector.inspect(document)
        let golden = try String(
            contentsOf: FixtureLocator.goldenURL("f01-simple-25fps.inspect.golden.txt"),
            encoding: .utf8)
        #expect(report.renderedText == golden)
    }
}

@Suite("Validator")
struct ValidatorTests {
    @Test func cleanFixtureHasNoFindings() throws {
        let document = try FCPXMLDocument(
            path: FixtureLocator.fixturePath("valid/f01-simple-25fps.fcpxml"))
        let report = Validator.validate(document)
        #expect(report.findings.isEmpty, "unexpected findings: \(report.renderedText)")
        #expect(!report.hasErrors)
    }

    @Test func badTimesAreErrors() throws {
        let document = try FCPXMLDocument(
            path: FixtureLocator.fixturePath("invalid/e03-bad-time.fcpxml"))
        let report = Validator.validate(document)
        #expect(report.hasErrors)
        let messages = report.findings.map(\.message).joined(separator: "\n")
        #expect(messages.contains("1.5s"))
        #expect(messages.contains("1/0s"))
    }

    @Test func danglingRefsAreErrors() throws {
        let document = try FCPXMLDocument(
            path: FixtureLocator.fixturePath("invalid/e04-dangling-ref.fcpxml"))
        let report = Validator.validate(document)
        #expect(report.hasErrors)
        let errors = report.findings.filter { $0.severity == .error }
        #expect(errors.contains { $0.message.contains("r99") })
    }

    @Test func unknownVersionIsAWarningNotAnError() throws {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<fcpxml version=\"99.7\"/>\n"
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("reedit-validator-\(UUID().uuidString).fcpxml")
        try Data(xml.utf8).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let document = try FCPXMLDocument(path: path.path)
        let report = Validator.validate(document)
        #expect(!report.hasErrors)
        #expect(report.findings.contains { $0.severity == .warning && $0.message.contains("99.7") })
    }
}
