import Foundation
import Testing

@testable import ReEditXML

@Suite("FCPXMLWriter")
struct WriterTests {
    /// Serializes an in-memory document through the same path as production.
    private func roundtrip(_ xml: String) throws -> (output: String, byteIdentical: Bool) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("reedit-writer-\(UUID().uuidString).fcpxml")
        try Data(xml.utf8).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let document = try FCPXMLDocument(path: path.path)
        let (output, report) = RoundtripVerifier.verify(document)
        return (String(decoding: output, as: UTF8.self), report.byteIdentical)
    }

    @Test func textEscaping() {
        #expect(FCPXMLWriter.escapeText("Harper & James") == "Harper &amp; James")
        #expect(FCPXMLWriter.escapeText("a < b > c") == "a &lt; b &gt; c")
        #expect(FCPXMLWriter.escapeText("plain") == "plain")
        // Quotes stay literal in text content, matching FCP output.
        #expect(FCPXMLWriter.escapeText("say \"cheese\"") == "say \"cheese\"")
        // A bare CR would be normalised to LF by any XML reparse; escape it.
        #expect(FCPXMLWriter.escapeText("a\rb") == "a&#13;b")
        // LF stays literal in text content.
        #expect(FCPXMLWriter.escapeText("a\nb") == "a\nb")
    }

    @Test func attributeEscaping() {
        #expect(FCPXMLWriter.escapeAttribute("Harper & James") == "Harper &amp; James")
        #expect(FCPXMLWriter.escapeAttribute("say \"cheese\"") == "say &quot;cheese&quot;")
        // Newlines in title text attributes must survive as numeric references.
        #expect(FCPXMLWriter.escapeAttribute("line one\nline two") == "line one&#10;line two")
        #expect(FCPXMLWriter.escapeAttribute("tab\there") == "tab&#9;here")
        #expect(FCPXMLWriter.escapeAttribute("cr\rhere") == "cr&#13;here")
    }

    @Test func selfClosesChildlessElements() throws {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<fcpxml version=\"1.11\">\n    <resources/>\n</fcpxml>\n"
        let result = try roundtrip(xml)
        #expect(result.byteIdentical, "output was:\n\(result.output)")
    }

    @Test func preservesCommentsAndWhitespace() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE fcpxml>
            <fcpxml version="1.11">
                <!-- editor note: locked section -->
                <resources/>
            </fcpxml>

            """
        let result = try roundtrip(xml)
        #expect(result.byteIdentical, "output was:\n\(result.output)")
    }

    @Test func preservesAttributeEntitiesByteExactly() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <fcpxml version="1.11">
                <marker start="0s" value="Harper &amp; James &#10;second line"/>
            </fcpxml>

            """
        let result = try roundtrip(xml)
        #expect(result.byteIdentical, "output was:\n\(result.output)")
    }

    @Test func preservesTextContentByteExactly() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <fcpxml version="1.11">
                <note>Tighten the pause &amp; check levels</note>
            </fcpxml>

            """
        let result = try roundtrip(xml)
        #expect(result.byteIdentical, "output was:\n\(result.output)")
    }

    @Test func noDoctypeMeansNoDoctypeInOutput() throws {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<fcpxml version=\"1.11\"/>\n"
        let result = try roundtrip(xml)
        #expect(result.byteIdentical, "output was:\n\(result.output)")
        #expect(!result.output.contains("DOCTYPE"))
    }

    @Test func missingTrailingNewlineIsPreserved() throws {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<fcpxml version=\"1.11\"/>"
        let result = try roundtrip(xml)
        #expect(result.byteIdentical, "output was:\n\(result.output)")
        #expect(!result.output.hasSuffix("\n"))
    }

    @Test func nonCanonicalIndentationNormalises() throws {
        // The writer owns formatting (ADR-0004): a two-space-indented source
        // re-emits in canonical four-space style. Bytes differ; meaning does
        // not — the canonical comparison tier covers such files.
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <fcpxml version="1.11">
              <resources>
                <format id="r1" frameDuration="100/2500s"/>
              </resources>
            </fcpxml>

            """
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("reedit-writer-\(UUID().uuidString).fcpxml")
        try Data(xml.utf8).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let document = try FCPXMLDocument(path: path.path)
        let (output, report) = RoundtripVerifier.verify(document)
        #expect(!report.byteIdentical)
        #expect(report.canonicallyIdentical)
        let expected = """
            <?xml version="1.0" encoding="UTF-8"?>
            <fcpxml version="1.11">
                <resources>
                    <format id="r1" frameDuration="100/2500s"/>
                </resources>
            </fcpxml>

            """
        #expect(String(decoding: output, as: UTF8.self) == expected)
    }

    @Test func mixedContentStaysInline() throws {
        // Whitespace inside title text is meaning, not formatting: <text>
        // subtrees emit children inline and never filter whitespace.
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <fcpxml version="1.11">
                <text>
                    <text-style ref="ts1">Harper &amp; James</text-style>
                </text>
            </fcpxml>

            """
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("reedit-writer-\(UUID().uuidString).fcpxml")
        try Data(xml.utf8).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let document = try FCPXMLDocument(path: path.path)
        let (output, report) = RoundtripVerifier.verify(document)
        let text = String(decoding: output, as: UTF8.self)
        // The text-style run itself must survive exactly.
        #expect(text.contains("<text-style ref=\"ts1\">Harper &amp; James</text-style>"))
        #if os(Linux)
            // Linux's parser retains the whitespace nodes, so the inline
            // emitter reproduces the source byte-for-byte. Darwin's parser
            // drops them before the writer runs (ADR-0004 platform note).
            #expect(report.byteIdentical)
        #endif
        #expect(report.canonicallyIdentical)
    }

    @Test func spaceOnlyTitleRunIsPreservedNotSelfClosed() throws {
        // A space-only styled run is title content — deleting it would change
        // the rendered title (review finding). Inline mode must keep it.
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            + "<fcpxml version=\"1.11\">\n"
            + "    <text><text-style ref=\"ts1\">Harper</text-style>"
            + "<text-style ref=\"ts2\"> </text-style>"
            + "<text-style ref=\"ts3\">James</text-style></text>\n"
            + "</fcpxml>\n"
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("reedit-writer-\(UUID().uuidString).fcpxml")
        try Data(xml.utf8).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let document = try FCPXMLDocument(path: path.path)
        let (output, report) = RoundtripVerifier.verify(document)
        let text = String(decoding: output, as: UTF8.self)
        #if os(Linux)
            #expect(report.byteIdentical, "output was:\n\(text)")
            #expect(text.contains("<text-style ref=\"ts2\"> </text-style>"))
        #else
            // Darwin's parser drops the whitespace-only run before the writer
            // sees it — a documented platform limitation (ADR-0004) checked at
            // the Final Cut import gate. The run element itself must survive.
            #expect(text.contains("ref=\"ts2\""))
        #endif
    }

    @Test func prologCommentBeforeDoctypeSurvives() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!-- exported for review -->
            <!DOCTYPE fcpxml>
            <fcpxml version="1.11">
                <resources/>
            </fcpxml>

            """
        let result = try roundtrip(xml)
        #expect(result.byteIdentical, "output was:\n\(result.output)")
        #expect(result.output.contains("<!-- exported for review -->"))
        #expect(result.output.contains("<!DOCTYPE fcpxml>"))
    }

    @Test func doctypeInternalSubsetSurvives() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE fcpxml [
            <!ENTITY nbsp "&#160;">
            ]>
            <fcpxml version="1.11">
                <resources/>
            </fcpxml>

            """
        let result = try roundtrip(xml)
        #expect(result.byteIdentical, "output was:\n\(result.output)")
    }

    @Test func byteOrderMarkSurvives() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<fcpxml version=\"1.11\"/>\n".utf8))
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("reedit-writer-\(UUID().uuidString).fcpxml")
        try data.write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let document = try FCPXMLDocument(path: path.path)
        #expect(document.prolog.hasByteOrderMark)
        let (output, report) = RoundtripVerifier.verify(document)
        #expect(report.byteIdentical, "output bytes: \(Array(output.prefix(8)))")
    }
}
