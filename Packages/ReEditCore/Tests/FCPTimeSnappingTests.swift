import Testing

@testable import ReEditCore

@Suite("FCPTime frame snapping")
struct FCPTimeSnappingTests {
    static let grids: [String] = [
        "1/24s", "1/25s", "1/30s", "1001/24000s", "1001/30000s", "1/44100s",
    ]

    @Test(arguments: grids)
    func exactMultiplesAreAligned(grid: String) throws {
        let frameDuration = try FCPTime(fcpxmlString: grid)
        for n: Int64 in [-3, -1, 0, 1, 2, 100, 25025] {
            let time = try frameDuration.multiplied(by: n)
            #expect(time.isAligned(toGrid: frameDuration))
            #expect(try time.frameIndex(grid: frameDuration) == n)
            for rule: FrameSnapRule in [.down, .up, .nearest] {
                #expect(try time.snapped(toGrid: frameDuration, rule: rule) == time)
            }
        }
    }

    @Test func misalignedTimesSnapOn25FpsGrid() throws {
        let grid = try FCPTime(fcpxmlString: "1/25s")
        // 3/50s is exactly 1.5 frames.
        let midpoint = try FCPTime(fcpxmlString: "3/50s")
        #expect(!midpoint.isAligned(toGrid: grid))
        #expect(try midpoint.snapped(toGrid: grid, rule: .down) == FCPTime(fcpxmlString: "1/25s"))
        #expect(try midpoint.snapped(toGrid: grid, rule: .up) == FCPTime(fcpxmlString: "2/25s"))
        // Documented tie rule: exact midpoints round down (toward -inf).
        #expect(try midpoint.snapped(toGrid: grid, rule: .nearest) == FCPTime(fcpxmlString: "1/25s"))

        // 7/100s is 1.75 frames: nearest rounds up.
        let closerToTwo = try FCPTime(fcpxmlString: "7/100s")
        #expect(try closerToTwo.snapped(toGrid: grid, rule: .nearest) == FCPTime(fcpxmlString: "2/25s"))
        // 1/20s is 1.25 frames: nearest rounds down.
        let closerToOne = try FCPTime(fcpxmlString: "1/20s")
        #expect(try closerToOne.snapped(toGrid: grid, rule: .nearest) == FCPTime(fcpxmlString: "1/25s"))
    }

    @Test func negativeTimesFloorTowardNegativeInfinity() throws {
        let grid = try FCPTime(fcpxmlString: "1/25s")
        // -1/50s is exactly -0.5 frames.
        let negativeMidpoint = try FCPTime(fcpxmlString: "-1/50s")
        #expect(try negativeMidpoint.frameIndex(grid: grid, rounding: .down) == -1)
        #expect(try negativeMidpoint.frameIndex(grid: grid, rounding: .up) == 0)
        #expect(try negativeMidpoint.frameIndex(grid: grid, rounding: .nearest) == -1)
        #expect(try negativeMidpoint.snapped(toGrid: grid, rule: .down) == FCPTime(fcpxmlString: "-1/25s"))
        #expect(try negativeMidpoint.snapped(toGrid: grid, rule: .up) == .zero)

        // -1.25 frames: down -> -2, up -> -1, nearest -> -1.
        let negativeQuarter = try FCPTime(fcpxmlString: "-1/20s")
        #expect(try negativeQuarter.frameIndex(grid: grid, rounding: .down) == -2)
        #expect(try negativeQuarter.frameIndex(grid: grid, rounding: .up) == -1)
        #expect(try negativeQuarter.frameIndex(grid: grid, rounding: .nearest) == -1)
    }

    @Test func ntscGridSnapping() throws {
        let grid = try FCPTime(fcpxmlString: "1001/30000s")
        // 1/30s is 1000/1001 of an NTSC frame: not aligned, nearest rounds up.
        let almostOneFrame = try FCPTime(fcpxmlString: "1/30s")
        #expect(!almostOneFrame.isAligned(toGrid: grid))
        #expect(try almostOneFrame.frameIndex(grid: grid, rounding: .down) == 0)
        #expect(try almostOneFrame.frameIndex(grid: grid, rounding: .up) == 1)
        #expect(try almostOneFrame.frameIndex(grid: grid, rounding: .nearest) == 1)

        // A time expressed on a coarser but compatible timescale stays aligned.
        let aligned = try FCPTime(fcpxmlString: "2002/30000s")
        #expect(aligned.isAligned(toGrid: grid))
        #expect(try aligned.frameIndex(grid: grid) == 2)
    }

    @Test func audioRateGrid() throws {
        let grid = try FCPTime(fcpxmlString: "1/44100s")
        let oneHour = FCPTime(seconds: 3600)
        #expect(oneHour.isAligned(toGrid: grid))
        #expect(try oneHour.frameIndex(grid: grid) == 158_760_000)
    }

    @Test func videoTimesAreOftenMisalignedOnAudioGrid() throws {
        let audioGrid = try FCPTime(fcpxmlString: "1/44100s")
        let ntscFrame = try FCPTime(fcpxmlString: "1001/30000s")
        #expect(!ntscFrame.isAligned(toGrid: audioGrid))
    }

    @Test func invalidGridsAreRejected() throws {
        let time = FCPTime(seconds: 1)
        #expect(!time.isAligned(toGrid: .zero))
        let negativeGrid = try FCPTime(fcpxmlString: "-1/25s")
        #expect(!time.isAligned(toGrid: negativeGrid))
        #expect(throws: FCPTimeError.self) {
            _ = try time.frameIndex(grid: .zero)
        }
        #expect(throws: FCPTimeError.self) {
            _ = try time.snapped(toGrid: negativeGrid, rule: .down)
        }
    }

    @Test func extremeValuesOverflowSafely() {
        let extreme = FCPTime(seconds: Int64.max)
        let fineGrid = try? FCPTime(fcpxmlString: "1/44100s")
        #expect(fineGrid != nil)
        if let fineGrid {
            // Int64.max * 44100 overflows: must throw, not trap or approximate.
            #expect(throws: FCPTimeError.self) {
                _ = try extreme.frameIndex(grid: fineGrid)
            }
        }
    }
}
