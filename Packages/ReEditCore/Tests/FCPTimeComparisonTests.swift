import Testing

@testable import ReEditCore

@Suite("FCPTime comparison")
struct FCPTimeComparisonTests {
    @Test func strictlyAscendingChain() throws {
        // Hand-ordered strictly ascending values across mixed denominators.
        let chain: [FCPTime] = try [
            FCPTime(seconds: Int64.min),
            FCPTime(fcpxmlString: "-3600s"),
            FCPTime(fcpxmlString: "-1/25s"),
            FCPTime(fcpxmlString: "-1/30000s"),
            .zero,
            FCPTime(fcpxmlString: "1/44100s"),
            FCPTime(fcpxmlString: "1/30s"),
            FCPTime(fcpxmlString: "1001/30000s"),
            FCPTime(fcpxmlString: "1/25s"),
            FCPTime(fcpxmlString: "1s"),
            FCPTime(fcpxmlString: "1001/1000s"),
            FCPTime(fcpxmlString: "3600s"),
            FCPTime(seconds: Int64.max),
        ]
        for i in chain.indices {
            for j in chain.indices {
                #expect(
                    (chain[i] < chain[j]) == (i < j),
                    "chain[\(i)] (\(chain[i])) < chain[\(j)] (\(chain[j])) must be \(i < j)")
                #expect((chain[i] == chain[j]) == (i == j))
            }
        }
    }

    @Test func crossMultiplicationCannotOverflow() throws {
        // Cross products here exceed Int64 by far; full-width comparison must
        // still order them exactly. x/(x+1) grows with x.
        let bigger = try FCPTime(numerator: Int64.max - 1, denominator: Int64.max)
        let smaller = try FCPTime(numerator: Int64.max - 2, denominator: Int64.max - 1)
        #expect(smaller < bigger)
        #expect(!(bigger < smaller))
        #expect(bigger != smaller)

        let negBigger = try FCPTime(numerator: -(Int64.max - 2), denominator: Int64.max - 1)
        let negSmaller = try FCPTime(numerator: -(Int64.max - 1), denominator: Int64.max)
        #expect(negSmaller < negBigger)
        #expect(negSmaller < smaller)
    }

    @Test func nearIdenticalNtscValues() throws {
        // 1001/30000 vs 1000/29971 differ by ~1e-9 s; exact comparison must
        // resolve it. 1001*29971 = 30000971 > 1000*30000 = 30000000.
        let a = try FCPTime(fcpxmlString: "1001/30000s")
        let b = try FCPTime(fcpxmlString: "1000/29971s")
        #expect(b < a)
    }

    @Test func sortingUsesTotalOrder() throws {
        let unsorted: [FCPTime] = try [
            FCPTime(fcpxmlString: "1/25s"),
            .zero,
            FCPTime(fcpxmlString: "-1/25s"),
            FCPTime(fcpxmlString: "1001/30000s"),
            FCPTime(fcpxmlString: "1/30s"),
        ]
        let sorted = unsorted.sorted()
        let expected: [FCPTime] = try [
            FCPTime(fcpxmlString: "-1/25s"),
            .zero,
            FCPTime(fcpxmlString: "1/30s"),
            FCPTime(fcpxmlString: "1001/30000s"),
            FCPTime(fcpxmlString: "1/25s"),
        ]
        #expect(sorted == expected)
    }

    @Test func comparableDerivedOperators() throws {
        let small = try FCPTime(fcpxmlString: "1/30s")
        let large = try FCPTime(fcpxmlString: "1/25s")
        #expect(small <= large)
        #expect(large >= small)
        #expect(small <= small)
        #expect(large > small)
    }
}
