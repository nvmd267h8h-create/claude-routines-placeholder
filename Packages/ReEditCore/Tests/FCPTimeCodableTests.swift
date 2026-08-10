import Foundation
import Testing

@testable import ReEditCore

@Suite("FCPTime Codable")
struct FCPTimeCodableTests {
    @Test(arguments: ["0s", "3600s", "1001/30000s", "-1/25s", "1/44100s"])
    func encodesAsCanonicalString(canonical: String) throws {
        let time = try FCPTime(fcpxmlString: canonical)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode([time])
        let json = String(decoding: data, as: UTF8.self)
        #expect(json == "[\"\(canonical)\"]")
        let decoded = try JSONDecoder().decode([FCPTime].self, from: data)
        #expect(decoded == [time])
    }

    @Test func decodingNormalisesNonReducedStrings() throws {
        let data = Data("[\"100/2500s\"]".utf8)
        let decoded = try JSONDecoder().decode([FCPTime].self, from: data)
        #expect(decoded == [try FCPTime(fcpxmlString: "1/25s")])
        #expect(decoded[0].fcpxmlString == "1/25s")
    }

    @Test(arguments: ["[\"1.5s\"]", "[\"1/0s\"]", "[\"\"]", "[1.5]", "[3600]"])
    func rejectsInvalidPayloads(json: String) {
        #expect(throws: Error.self) {
            _ = try JSONDecoder().decode([FCPTime].self, from: Data(json.utf8))
        }
    }

    @Test func nestedInStructures() throws {
        struct Range: Codable, Equatable {
            let start: FCPTime
            let duration: FCPTime
        }
        let range = Range(
            start: try FCPTime(fcpxmlString: "857s"),
            duration: try FCPTime(fcpxmlString: "42/25s"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = String(decoding: try encoder.encode(range), as: UTF8.self)
        #expect(json == "{\"duration\":\"42/25s\",\"start\":\"857s\"}")
        let decoded = try JSONDecoder().decode(Range.self, from: Data(json.utf8))
        #expect(decoded == range)
    }
}
