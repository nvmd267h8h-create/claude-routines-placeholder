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
    /// A non-positive grid never aligns anything and returns `false`.
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
        // self / frameDuration = (num * fd.den) / (den * fd.num); both stored
        // fractions are reduced, but the cross products can still overflow for
        // extreme values — checked, never approximated.
        let (dividend, o1) = numerator.multipliedReportingOverflow(
            by: frameDuration.denominator)
        let (divisor, o2) = denominator.multipliedReportingOverflow(
            by: frameDuration.numerator)
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
