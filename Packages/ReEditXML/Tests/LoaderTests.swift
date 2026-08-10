import Foundation
import ReEditCore
import Testing

@testable import ReEditXML

@Suite("FCPXML loading")
struct LoaderTests {
    @Test func loadsSimpleFixture() throws {
        let document = try FCPXMLDocument(
            path: FixtureLocator.fixturePath("valid/f01-simple-25fps.fcpxml"))
        #expect(document.version == "1.11")
        #expect(document.input.kind == .file)
        #expect(!document.sourceData.isEmpty)
        #expect(document.sourceFingerprint.count == 64)
    }

    @Test func prologScanSeesDeclarationAndDoctype() throws {
        let document = try FCPXMLDocument(
            path: FixtureLocator.fixturePath("valid/f01-simple-25fps.fcpxml"))
        #expect(document.prolog.xmlDeclaration == "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        #expect(document.prolog.doctype == "<!DOCTYPE fcpxml>")
        #expect(document.prolog.endsWithNewline)
    }

    @Test func prologScanHandlesMissingPieces() {
        let bare = PrologInfo.scan(Data("<fcpxml version=\"1.11\"/>".utf8))
        #expect(bare.xmlDeclaration == nil)
        #expect(bare.doctype == nil)
        #expect(!bare.endsWithNewline)

        let declarationOnly = PrologInfo.scan(
            Data("<?xml version=\"1.0\"?>\n<fcpxml version=\"1.11\"/>\n".utf8))
        #expect(declarationOnly.xmlDeclaration == "<?xml version=\"1.0\"?>")
        #expect(declarationOnly.doctype == nil)
        #expect(declarationOnly.endsWithNewline)
    }

    @Test func sourceVersionIsKeptVerbatim() throws {
        // A future version string must never be normalised or upgraded.
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<fcpxml version=\"99.7\"/>\n"
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("reedit-version-test-\(UUID().uuidString).fcpxml")
        try Data(xml.utf8).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let document = try FCPXMLDocument(path: path.path)
        #expect(document.version == "99.7")
    }

    @Test func loadingNeverMutatesTheSourceFile() throws {
        let fixturePath = FixtureLocator.fixturePath("valid/f01-simple-25fps.fcpxml")
        let before = try Data(contentsOf: URL(fileURLWithPath: fixturePath))
        let document = try FCPXMLDocument(path: fixturePath)
        _ = RoundtripVerifier.verify(document)
        let after = try Data(contentsOf: URL(fileURLWithPath: fixturePath))
        #expect(before == after)
    }
}

@Suite("Bundle resolution")
struct BundleTests {
    @Test func rejectsBundleWithoutDocument() {
        #expect(throws: FCPXMLLoadError.self) {
            _ = try FCPXMLInput.resolve(
                path: FixtureLocator.fixturePath("invalid/e05-empty-bundle.fcpxmld"),
                fileSystem: LiveFileSystem())
        }
    }

    @Test func resolvesPlainFile() throws {
        let input = try FCPXMLInput.resolve(
            path: FixtureLocator.fixturePath("valid/f01-simple-25fps.fcpxml"),
            fileSystem: LiveFileSystem())
        #expect(input.kind == .file)
        #expect(input.documentPath == input.inputPath)
    }

    @Test func resolvesBundleWithTrailingSlash() throws {
        // Shell tab completion appends '/' to directories; the bundle must
        // still be recognised.
        let input = try FCPXMLInput.resolve(
            path: FixtureLocator.fixturePath("valid/f06-bundle.fcpxmld") + "/",
            fileSystem: LiveFileSystem())
        #expect(input.kind == .bundle(innerDocumentName: "Info.fcpxml"))
        #expect(input.documentPath.hasSuffix("f06-bundle.fcpxmld/Info.fcpxml"))
    }
}
