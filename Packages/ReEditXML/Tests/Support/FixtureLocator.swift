import Foundation

/// Locates repository fixtures from test code by walking up from this source
/// file to the directory containing `Package.swift`.
///
/// Tests therefore run against the checkout on every platform; they are not
/// relocatable as a prebuilt binary, which is acceptable for Phase 0.
enum FixtureLocator {
    static let repoRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            let manifest = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: manifest.path) {
                return url
            }
        }
        fatalError("Package.swift not found above \(#filePath)")
    }()

    /// Absolute path of a fixture under `Tests/Fixtures/`.
    static func fixturePath(_ relative: String) -> String {
        repoRoot.appendingPathComponent("Tests/Fixtures").appendingPathComponent(relative).path
    }

    /// URL of a golden file under `Tests/GoldenFiles/`.
    static func goldenURL(_ name: String) -> URL {
        repoRoot.appendingPathComponent("Tests/GoldenFiles").appendingPathComponent(name)
    }

    /// Whether golden recording mode is active (REEDIT_RECORD_GOLDENS=1).
    /// In record mode, golden tests print actual output between markers instead
    /// of asserting, so CI logs can seed the committed goldens.
    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["REEDIT_RECORD_GOLDENS"] == "1"
    }
}
