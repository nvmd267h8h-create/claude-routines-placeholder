/// Errors thrown by `FCPTime` construction, parsing, arithmetic and grid operations.
///
/// Every case carries enough context to explain the failure to a user; `description`
/// includes recovery guidance where one exists.
public enum FCPTimeError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The input string is not valid FCPXML time notation (`-?digits(/digits)?s`).
    case parseFailure(input: String, reason: String)

    /// A rational time was constructed with a zero or negative denominator.
    case nonPositiveDenominator(Int64)

    /// An exact operation would exceed the representable `Int64` range.
    /// ReEdit never approximates: the operation fails instead.
    case overflow(operation: String, lhs: String, rhs: String?)

    /// A frame-grid operation was given a non-positive grid duration.
    case invalidFrameGrid(grid: String)

    /// A `CMTime` that is not numeric (invalid, indefinite or infinite) cannot
    /// become an `FCPTime`.
    case cmTimeNotNumeric(details: String)

    /// The reduced denominator does not fit `CMTimeScale` (`Int32`); converting
    /// would require a lossy rescale, which ReEdit refuses to do.
    case cmTimescaleUnrepresentable(denominator: Int64)

    public var description: String {
        switch self {
        case .parseFailure(let input, let reason):
            return "Cannot parse '\(input)' as an FCPXML time: \(reason). "
                + "Expected forms like '3600s', '1001/30000s' or '-1/25s'."
        case .nonPositiveDenominator(let denominator):
            return "Rational time denominator must be positive, got \(denominator)."
        case .overflow(let operation, let lhs, let rhs):
            let operands = rhs.map { "\(lhs) and \($0)" } ?? lhs
            return "Exact time \(operation) overflowed 64-bit range for \(operands). "
                + "The operation was rejected rather than approximated."
        case .invalidFrameGrid(let grid):
            return "Frame grid duration must be positive, got '\(grid)'."
        case .cmTimeNotNumeric(let details):
            return "CMTime is not numeric (\(details)) and cannot become an exact rational time."
        case .cmTimescaleUnrepresentable(let denominator):
            return "Denominator \(denominator) exceeds CMTimeScale range; refusing lossy conversion. "
                + "Keep the value as FCPTime for edit logic."
        }
    }
}
