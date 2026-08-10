/// Rounding rule for snapping a time onto a frame grid.
public enum FrameSnapRule: Sendable {
    /// Toward negative infinity.
    case down
    /// Toward positive infinity.
    case up
    /// To the closer frame boundary; exact midpoints round down (toward -inf).
    case nearest
}

extension FCPTime {
    /// Whether this time lies exactly on the grid of `frameDuration` multiples.
    ///
    /// A non-positive grid never aligns anything and returns `false`.
    /// Documented boundary: when the cross products overflow even after
    /// gcd reduction (times beyond ~10^17 seconds on fine grids — far outside
    /// any timeline), this returns `false` rather than answering exactly;
    /// `frameIndex(grid:rounding:)` throws `.overflow` for the same input, so
    /// callers needing a hard guarantee use the throwing API.
    public func isAligned(toGrid frameDuration: FCPTime) -> Bool {
        guard frameDuration.numerator > 0 else { return false }
        guard let division = try? gridDivision(by: frameDuration) else { return false }
        return division.remainder == 0
    }

    /// The index of the frame boundary selected by `rounding` on the given grid.
    ///
    /// `frameIndex(grid: g, rounding: .down)` of an aligned time `n*g` is exactly `n`;
    /// negative times floor correctly (e.g. `-1/50s` on a `1/25s` grid floors to -1).
    public func frameIndex(
        grid frameDuration: FCPTime, rounding: FrameSnapRule = .down
    ) throws(FCPTimeError) -> Int64 {
        guard frameDuration.numerator > 0 else {
            throw FCPTimeError.invalidFrameGrid(grid: frameDuration.fcpxmlString)
        }
        let division = try gridDivision(by: frameDuration)
        if division.remainder == 0 {
            return division.floorQuotient
        }
        switch rounding {
        case .down:
            return division.floorQuotient
        case .up:
            let (up, overflow) = division.floorQuotient.addingReportingOverflow(1)
            guard !overflow else {
                throw FCPTimeError.overflow(
                    operation: "frame rounding", lhs: fcpxmlString,
                    rhs: frameDuration.fcpxmlString)
            }
            return up
        case .nearest:
            // Round up only when remainder > half the divisor. Comparing
            // remainder against (divisor - remainder) avoids overflow; the
            // exact midpoint (equal halves) rounds down, as documented.
            if division.remainder > division.divisor - division.remainder {
                let (up, overflow) = division.floorQuotient.addingReportingOverflow(1)
                guard !overflow else {
                    throw FCPTimeError.overflow(
                        operation: "frame rounding", lhs: fcpxmlString,
                        rhs: frameDuration.fcpxmlString)
                }
                return up
            }
            return division.floorQuotient
        }
    }

    /// This time snapped onto the frame grid using `rule`.
    public func snapped(
        toGrid frameDuration: FCPTime, rule: FrameSnapRule
    ) throws(FCPTimeError) -> FCPTime {
        let index = try frameIndex(grid: frameDuration, rounding: rule)
        return try frameDuration.multiplied(by: index)
    }

    /// Exact division of `self` by a positive grid, as a floored quotient plus a
    /// non-negative remainder over `divisor` (`0 <= remainder < divisor`).
    private func gridDivision(
        by frameDuration: FCPTime
    ) throws(FCPTimeError) -> (floorQuotient: Int64, remainder: Int64, divisor: Int64) {
        // self / frameDuration = (num * fd.den) / (den * fd.num). Cancel
        // common factors across the fractions first (each is internally
        // reduced already) — the ratio, floor and remainder-zero facts are
        // unchanged and the overflow window shrinks dramatically. Remaining
        // overflow for absurd magnitudes is checked, never approximated.
        let crossA = FCPTime.gcd(numerator.magnitude, frameDuration.numerator.magnitude)
        let crossB = FCPTime.gcd(UInt64(denominator), UInt64(frameDuration.denominator))
        let reducedNumerator = crossA > 1 ? numerator / Int64(crossA) : numerator
        let reducedGridNumerator =
            crossA > 1 ? frameDuration.numerator / Int64(crossA) : frameDuration.numerator
        let reducedDenominator = crossB > 1 ? denominator / Int64(crossB) : denominator
        let reducedGridDenominator =
            crossB > 1 ? frameDuration.denominator / Int64(crossB) : frameDuration.denominator

        let (dividend, o1) = reducedNumerator.multipliedReportingOverflow(
            by: reducedGridDenominator)
        let (divisor, o2) = reducedDenominator.multipliedReportingOverflow(
            by: reducedGridNumerator)
        guard !o1, !o2 else {
            throw FCPTimeError.overflow(
                operation: "frame-grid division", lhs: fcpxmlString,
                rhs: frameDuration.fcpxmlString)
        }
        // Swift's / and % truncate toward zero; convert to floored (Euclidean)
        // so negative times land on the boundary at or below them.
        var quotient = dividend / divisor
        var remainder = dividend % divisor
        if remainder < 0 {
            quotient -= 1
            remainder += divisor
        }
        return (quotient, remainder, divisor)
    }
}
