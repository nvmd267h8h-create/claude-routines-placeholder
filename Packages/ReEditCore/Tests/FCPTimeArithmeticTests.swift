import Testing

@testable import ReEditCore

@Suite("FCPTime arithmetic")
struct FCPTimeArithmeticTests {
    static let sumCases: [(lhs: String, rhs: String, sum: String)] = [
        ("0s", "0s", "0s"),
        ("1s", "2s", "3s"),
        ("1/25s", "1/30s", "11/150s"),
        ("1001/30000s", "999/1000s", "30971/30000s"),
        ("1/25s", "-1/25s", "0s"),
        ("-1/25s", "-1/25s", "-2/25s"),
        ("3600s", "1001/30000s", "108001001/30000s"),
        ("1/44100s", "1/30000s", "247/4410000s"),  // over lcm(44100, 30000) = 4410000
        ("1/2s", "1/2s", "1s"),
        ("1/3s", "2/3s", "1s"),
    ]

    @Test(arguments: sumCases.indices)
    func exactSums(index: Int) throws {
        let c = Self.sumCases[index]
        let lhs = try FCPTime(fcpxmlString: c.lhs)
        let rhs = try FCPTime(fcpxmlString: c.rhs)
        let expected = try FCPTime(fcpxmlString: c.sum)
        #expect(try lhs.adding(rhs) == expected)
        #expect(try rhs.adding(lhs) == expected, "addition must commute")
        #expect(try expected.subtracting(rhs) == lhs, "a+b-b == a")
        #expect(try expected.subtracting(lhs) == rhs, "a+b-a == b")
    }

    @Test func thirdsSumExactlyToOne() throws {
        let third = try FCPTime(numerator: 1, denominator: 3)
        let one = try third.adding(third).adding(third)
        #expect(one == FCPTime(seconds: 1))
    }

    @Test func repeatedNtscFrameAdditionStaysExact() throws {
        // 30000 frames of 1001/30000s each must equal exactly 1001 seconds.
        let frame = try FCPTime(fcpxmlString: "1001/30000s")
        var total = FCPTime.zero
        for _ in 0..<30000 {
            total = try total.adding(frame)
        }
        #expect(total == FCPTime(seconds: 1001))
    }

    @Test func additionOverflowThrows() throws {
        let max = FCPTime(seconds: Int64.max)
        #expect(throws: FCPTimeError.self) {
            _ = try max.adding(FCPTime(seconds: 1))
        }
        let min = FCPTime(seconds: Int64.min)
        #expect(throws: FCPTimeError.self) {
            _ = try min.subtracting(FCPTime(seconds: 1))
        }
        // Denominator LCM overflow: two large coprime denominators.
        let a = try FCPTime(numerator: 1, denominator: Int64.max)
        let b = try FCPTime(numerator: 1, denominator: Int64.max - 1)
        #expect(throws: FCPTimeError.self) {
            _ = try a.adding(b)
        }
    }

    @Test func negation() throws {
        let time = try FCPTime(fcpxmlString: "1001/30000s")
        #expect(try time.negated() == FCPTime(fcpxmlString: "-1001/30000s"))
        #expect(try FCPTime.zero.negated() == .zero)
        #expect(throws: FCPTimeError.self) {
            _ = try FCPTime(seconds: Int64.min).negated()
        }
    }

    @Test func scalarMultiplication() throws {
        let frame = try FCPTime(fcpxmlString: "1/25s")
        #expect(try frame.multiplied(by: 25) == FCPTime(seconds: 1))
        #expect(try frame.multiplied(by: 0) == .zero)
        #expect(try frame.multiplied(by: -3) == FCPTime(fcpxmlString: "-3/25s"))
        let ntsc = try FCPTime(fcpxmlString: "1001/30000s")
        #expect(try ntsc.multiplied(by: 30000) == FCPTime(seconds: 1001))
        #expect(throws: FCPTimeError.self) {
            _ = try FCPTime(seconds: Int64.max).multiplied(by: 2)
        }
    }

    @Test func sumsReduce() throws {
        let a = try FCPTime(fcpxmlString: "1/6s")
        let b = try FCPTime(fcpxmlString: "1/3s")
        let sum = try a.adding(b)  // 1/6 + 2/6 = 3/6 = 1/2
        #expect(sum.numerator == 1)
        #expect(sum.denominator == 2)
    }

    @Test func predicates() throws {
        #expect(FCPTime.zero.isZero)
        #expect(!FCPTime.zero.isNegative)
        let negative = try FCPTime(fcpxmlString: "-1/25s")
        #expect(negative.isNegative)
        #expect(!negative.isZero)
    }
}
