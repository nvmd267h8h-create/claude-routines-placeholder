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
        // Whitespace inside title text is meaning, not formatting: elements
        // with significant text emit children inline, untouched.
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
        let (output, _) = RoundtripVerifier.verify(document)
        let text = String(decoding: output, as: UTF8.self)
        // The text-style run itself must survive exactly.
        #expect(text.contains("<text-style ref=\"ts1\">Harper &amp; James</text-style>"))
    }
}
