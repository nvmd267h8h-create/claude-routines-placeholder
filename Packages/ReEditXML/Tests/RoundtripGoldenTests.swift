import Foundation
import Testing

@testable import ReEditXML

/// No-op roundtrip fidelity against committed goldens (spec §6.1, §10.3).
///
/// Synthetic fixtures are authored in the writer's canonical style, so Tier 1
/// (byte identity) is the gate on both platforms. Tier 2 (canonical identity)
/// must also always hold.
@Suite("No-op roundtrip goldens")
struct RoundtripGoldenTests {
    static let fixtures: [String] = [
        "valid/f01-simple-25fps.fcpxml",
        "valid/f02-connected-broll-music.fcpxml",
        "valid/f03-titles.fcpxml",
        "valid/f04-audio-roles.fcpxml",
        "valid/f05-gaps-transitions.fcpxml",
        "valid/f06-bundle.fcpxmld",
        "valid/f08-unknown-nodes.fcpxml",
    ]

    @Test(arguments: fixtures)
    func roundtripIsByteIdentical(fixture: String) throws {
        let document = try FCPXMLDocument(path: FixtureLocator.fixturePath(fixture))
        let (output, report) = RoundtripVerifier.verify(document)

        #expect(report.outputWellFormed)
        #expect(report.canonicallyIdentical, "canonical form drifted for \(fixture)")
        #expect(
            report.byteIdentical,
            "byte fidelity failed for \(fixture); output:\n\(String(decoding: output, as: UTF8.self))")

        // The committed golden pins the expected bytes independently of the
        // fixture file, so accidental edits to either are visible in review.
        let goldenName = goldenFileName(for: fixture)
        let goldenURL = FixtureLocator.goldenURL(goldenName)
        let golden = try Data(contentsOf: goldenURL)
        #expect(output == golden, "output differs from committed golden \(goldenName)")
    }

    @Test(arguments: fixtures)
    func fingerprintsMatchWhenNothingChanged(fixture: String) throws {
        let document = try FCPXMLDocument(path: FixtureLocator.fixturePath(fixture))
        let (_, report) = RoundtripVerifier.verify(document)
        // Spec §6.6: source and output fingerprints differ only when an edit
        // was intentionally applied. A no-op roundtrip of a canonical-style
        // fixture must reproduce identical bytes, hence identical fingerprints.
        #expect(report.sourceFingerprint == report.outputFingerprint)
    }

    @Test func generatedOutputNeverContainsStableIDs() throws {
        let document = try FCPXMLDocument(
            path: FixtureLocator.fixturePath("valid/f01-simple-25fps.fcpxml"))
        let (output, _) = RoundtripVerifier.verify(document)
        let text = String(decoding: output, as: UTF8.self)
        // Spec §6.3: identity lives in sidecar data, never in production XML.
        #expect(!text.contains("stableID"))
        #expect(!text.contains("reedit"))
    }

    private func goldenFileName(for fixture: String) -> String {
        let base = fixture
            .replacingOccurrences(of: "valid/", with: "")
            .replacingOccurrences(of: ".fcpxmld", with: "")
            .replacingOccurrences(of: ".fcpxml", with: "")
        return base + ".roundtrip.golden.fcpxml"
    }
}
