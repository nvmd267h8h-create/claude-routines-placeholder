import Testing

@testable import ReEditCore

@Suite("FCPTime parsing")
struct FCPTimeParsingTests {
    static let validCases: [(input: String, numerator: Int64, denominator: Int64)] = [
        ("0s", 0, 1),
        ("-0s", 0, 1),
        ("1s", 1, 1),
        ("-1s", -1, 1),
        ("3600s", 3600, 1),
        ("1/25s", 1, 25),
        ("-1/25s", -1, 25),
        ("100/2500s", 1, 25),  // non-reduced input reduces
        ("1001/30000s", 1001, 30000),
        ("-1001/30000s", -1001, 30000),
        ("1001/2400s", 1001, 2400),
        ("25025/25000s", 1001, 1000),  // non-reduced input reduces
        ("0/25s", 0, 1),  // zero normalises to 0/1
        ("-0/30000s", 0, 1),
        ("1/44100s", 1, 44100),  // subframe audio grid
        ("3137/44100s", 3137, 44100),
        ("3137134/44100s", 224081, 3150),  // reduces by gcd 14
        ("9223372036854775807s", Int64.max, 1),
        ("-9223372036854775808s", Int64.min, 1),
        ("9223372036854775807/9223372036854775807s", 1, 1),
    ]

    @Test(arguments: validCases.indices)
    func parsesValidNotation(index: Int) throws {
        let expected = Self.validCases[index]
        let time = try FCPTime(fcpxmlString: expected.input)
        #expect(time.numerator == expected.numerator)
        #expect(time.denominator == expected.denominator)
    }

    static let invalidInputs: [String] = [
        "",
        "s",
        "-s",
        "1",
        "1/25",
        "1.5s",
        "-1.5s",
        "1,5s",
        " 1s",
        "1s ",
        "1 s",
        "+1s",
        "--1s",
        "1//25s",
        "1/25/2s",
        "1/s",
        "/25s",
        "1/0s",
        "1/-25s",
        "0x10s",
        "1e3s",
        "abc",
        "9223372036854775808s",  // > Int64.max unsigned
        "-9223372036854775809s",  // < Int64.min
        "18446744073709551616s",  // > UInt64.max digits
        "1/9223372036854775808s",  // denominator > Int64.max
        "١s",  // non-ASCII digit
    ]

    @Test(arguments: invalidInputs)
    func rejectsInvalidNotation(input: String) {
        #expect(throws: FCPTimeError.self) {
            _ = try FCPTime(fcpxmlString: input)
        }
    }

    @Test(arguments: [
        "0s", "1s", "-1s", "3600s", "1/25s", "-1/25s", "1001/30000s", "1/44100s",
        "9223372036854775807s", "-9223372036854775808s",
    ])
    func canonicalStringsRoundtrip(input: String) throws {
        let time = try FCPTime(fcpxmlString: input)
        #expect(time.fcpxmlString == input)
        let reparsed = try FCPTime(fcpxmlString: time.fcpxmlString)
        #expect(reparsed == time)
    }

    @Test func nonReducedInputSerialisesReduced() throws {
        let time = try FCPTime(fcpxmlString: "100/2500s")
        #expect(time.fcpxmlString == "1/25s")
    }

    @Test func directInitRejectsNonPositiveDenominator() {
        #expect(throws: FCPTimeError.nonPositiveDenominator(0)) {
            _ = try FCPTime(numerator: 1, denominator: 0)
        }
        #expect(throws: FCPTimeError.nonPositiveDenominator(-25)) {
            _ = try FCPTime(numerator: 1, denominator: -25)
        }
    }

    @Test func directInitReduces() throws {
        let time = try FCPTime(numerator: -50, denominator: 100)
        #expect(time.numerator == -1)
        #expect(time.denominator == 2)
    }

    @Test func int64MinNumeratorIsRepresentable() throws {
        let time = try FCPTime(numerator: Int64.min, denominator: 3)
        #expect(time.numerator == Int64.min)
        #expect(time.denominator == 3)
        let halved = try FCPTime(numerator: Int64.min, denominator: 2)
        #expect(halved.numerator == Int64.min / 2)
        #expect(halved.denominator == 1)
    }

    @Test func secondsInitialiser() {
        let time = FCPTime(seconds: 857)
        #expect(time.numerator == 857)
        #expect(time.denominator == 1)
        #expect(FCPTime(seconds: 0) == .zero)
    }

    @Test func equalityIsSemantic() throws {
        let a = try FCPTime(numerator: 2, denominator: 50)
        let b = try FCPTime(numerator: 1, denominator: 25)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        let set: Set<FCPTime> = [a, b, .zero]
        #expect(set.count == 2)
    }
}
