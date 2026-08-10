#if canImport(CoreMedia)
    import CoreMedia
    import Testing

    @testable import ReEditCore

    // These tests exercise the Darwin-only CoreMedia interop and run on the
    // macOS CI job; Linux compiles them out.
    @Suite("FCPTime CMTime interop")
    struct FCPTimeCMTimeTests {
        @Test func roundtripsNumericTimes() throws {
            let original = CMTime(value: 1001, timescale: 30000)
            let time = try FCPTime(original)
            #expect(time.numerator == 1001)
            #expect(time.denominator == 30000)
            let back = try time.toCMTime()
            #expect(back.value == 1001)
            #expect(back.timescale == 30000)
        }

        @Test func reducesOnImport() throws {
            let time = try FCPTime(CMTime(value: 100, timescale: 2500))
            #expect(time.numerator == 1)
            #expect(time.denominator == 25)
        }

        @Test func rejectsNonNumericTimes() {
            #expect(throws: FCPTimeError.self) {
                _ = try FCPTime(CMTime.invalid)
            }
            #expect(throws: FCPTimeError.self) {
                _ = try FCPTime(CMTime.indefinite)
            }
            #expect(throws: FCPTimeError.self) {
                _ = try FCPTime(CMTime.positiveInfinity)
            }
        }

        @Test func refusesLossyTimescaleConversion() throws {
            // Denominator beyond Int32.max cannot become a CMTimeScale exactly.
            let fine = try FCPTime(numerator: 1, denominator: Int64(Int32.max) + 1)
            #expect(throws: FCPTimeError.cmTimescaleUnrepresentable(denominator: Int64(Int32.max) + 1)) {
                _ = try fine.toCMTime()
            }
        }

        @Test func zeroRoundtrips() throws {
            let zero = try FCPTime(CMTime.zero)
            #expect(zero == .zero)
            let back = try FCPTime.zero.toCMTime()
            #expect(back.seconds == 0)
        }
    }
#endif
