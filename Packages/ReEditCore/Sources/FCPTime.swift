/// An exact rational time value matching FCPXML notation (`3600s`, `1001/30000s`).
///
/// Values are always stored fully reduced with a positive denominator, so
/// synthesized equality and hashing are semantically correct. All arithmetic is
/// overflow-checked: operations either return an exact result or throw
/// `FCPTimeError.overflow` — they never trap, wrap or approximate. Floating point
/// is never used for edit logic (spec §5.3); it may be derived for display only.
public struct FCPTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// Signed numerator of the reduced fraction, in seconds.
    public let numerator: Int64
    /// Denominator of the reduced fraction. Invariant: always > 0.
    public let denominator: Int64

    /// Zero seconds (`0/1`).
    public static let zero = FCPTime(reducedNumerator: 0, reducedDenominator: 1)

    /// Trusted init for values already in canonical form. All public paths reduce.
    private init(reducedNumerator: Int64, reducedDenominator: Int64) {
        self.numerator = reducedNumerator
        self.denominator = reducedDenominator
    }

    /// Creates an exact rational time, reducing to canonical form.
    /// - Throws: `FCPTimeError.nonPositiveDenominator` when `denominator <= 0`.
    public init(numerator: Int64, denominator: Int64) throws(FCPTimeError) {
        guard denominator > 0 else {
            throw FCPTimeError.nonPositiveDenominator(denominator)
        }
        if numerator == 0 {
            self.init(reducedNumerator: 0, reducedDenominator: 1)
            return
        }
        let g = FCPTime.gcd(numerator.magnitude, UInt64(denominator))
        if g > 1 {
            // g divides both magnitudes exactly and g <= denominator < 2^63,
            // so the conversion and divisions are exact and cannot trap.
            let divisor = Int64(g)
            self.init(
                reducedNumerator: numerator / divisor,
                reducedDenominator: denominator / divisor
            )
        } else {
            self.init(reducedNumerator: numerator, reducedDenominator: denominator)
        }
    }

    /// Whole seconds (`seconds/1`).
    public init(seconds: Int64) {
        self.init(reducedNumerator: seconds, reducedDenominator: 1)
    }

    public var isZero: Bool { numerator == 0 }
    public var isNegative: Bool { numerator < 0 }

    // MARK: - FCPXML string form

    /// Parses strict FCPXML time notation: `-?digits(/digits)?s`.
    ///
    /// Accepted: `"0s"`, `"3600s"`, `"1001/30000s"`, `"-1/25s"`, non-reduced inputs
    /// (stored reduced). Rejected: decimals, whitespace, `+` signs, missing `s`,
    /// zero or signed denominators, and digit runs beyond `Int64`.
    public init(fcpxmlString: String) throws(FCPTimeError) {
        let bytes = Array(fcpxmlString.utf8)
        var index = 0

        guard !bytes.isEmpty else {
            throw FCPTimeError.parseFailure(input: fcpxmlString, reason: "empty string")
        }
        guard bytes.last == UInt8(ascii: "s") else {
            throw FCPTimeError.parseFailure(
                input: fcpxmlString, reason: "missing trailing 's'")
        }
        let end = bytes.count - 1

        var negative = false
        if index < end, bytes[index] == UInt8(ascii: "-") {
            negative = true
            index += 1
        }

        func scanDigits() throws(FCPTimeError) -> UInt64 {
            guard index < end, bytes[index] >= UInt8(ascii: "0"),
                bytes[index] <= UInt8(ascii: "9")
            else {
                throw FCPTimeError.parseFailure(
                    input: fcpxmlString, reason: "expected a digit at offset \(index)")
            }
            var value: UInt64 = 0
            while index < end, bytes[index] >= UInt8(ascii: "0"),
                bytes[index] <= UInt8(ascii: "9")
            {
                let digit = UInt64(bytes[index] - UInt8(ascii: "0"))
                let (shifted, mulOverflow) = value.multipliedReportingOverflow(by: 10)
                let (next, addOverflow) = shifted.addingReportingOverflow(digit)
                guard !mulOverflow, !addOverflow else {
                    throw FCPTimeError.parseFailure(
                        input: fcpxmlString, reason: "number exceeds 64-bit range")
                }
                value = next
                index += 1
            }
            return value
        }

        let magnitude = try scanDigits()

        var denominator: Int64 = 1
        if index < end, bytes[index] == UInt8(ascii: "/") {
            index += 1
            let rawDenominator = try scanDigits()
            guard rawDenominator > 0 else {
                throw FCPTimeError.parseFailure(
                    input: fcpxmlString, reason: "denominator must be positive")
            }
            guard rawDenominator <= UInt64(Int64.max) else {
                throw FCPTimeError.parseFailure(
                    input: fcpxmlString, reason: "denominator exceeds 64-bit range")
            }
            denominator = Int64(rawDenominator)
        }

        guard index == end else {
            throw FCPTimeError.parseFailure(
                input: fcpxmlString,
                reason: "unexpected character at offset \(index)")
        }

        let numerator: Int64
        if negative {
            // -(2^63) is representable as Int64.min.
            guard magnitude <= UInt64(Int64.max) + 1 else {
                throw FCPTimeError.parseFailure(
                    input: fcpxmlString, reason: "number exceeds 64-bit range")
            }
            numerator = magnitude == UInt64(Int64.max) + 1
                ? Int64.min
                : -Int64(magnitude)
        } else {
            guard magnitude <= UInt64(Int64.max) else {
                throw FCPTimeError.parseFailure(
                    input: fcpxmlString, reason: "number exceeds 64-bit range")
            }
            numerator = Int64(magnitude)
        }

        try self.init(numerator: numerator, denominator: denominator)
    }

    /// Canonical FCPXML notation: `"0s"`, `"3600s"`, `"1001/30000s"`, `"-1/25s"`.
    public var fcpxmlString: String {
        denominator == 1 ? "\(numerator)s" : "\(numerator)/\(denominator)s"
    }

    public var description: String { fcpxmlString }

    // MARK: - Checked arithmetic

    /// Exact sum. Throws `.overflow` instead of wrapping or approximating.
    public func adding(_ other: FCPTime) throws(FCPTimeError) -> FCPTime {
        try combined(with: other, operation: "addition", subtract: false)
    }

    /// Exact difference. Throws `.overflow` instead of wrapping or approximating.
    public func subtracting(_ other: FCPTime) throws(FCPTimeError) -> FCPTime {
        try combined(with: other, operation: "subtraction", subtract: true)
    }

    private func combined(
        with other: FCPTime, operation: String, subtract: Bool
    ) throws(FCPTimeError) -> FCPTime {
        // Scale over the least common multiple of the two denominators.
        let g = Int64(FCPTime.gcd(UInt64(denominator), UInt64(other.denominator)))
        let lhsScale = other.denominator / g
        let rhsScale = denominator / g

        let (lhsScaled, o1) = numerator.multipliedReportingOverflow(by: lhsScale)
        let (rhsScaled, o2) = other.numerator.multipliedReportingOverflow(by: rhsScale)
        let (resultNumerator, o3) = subtract
            ? lhsScaled.subtractingReportingOverflow(rhsScaled)
            : lhsScaled.addingReportingOverflow(rhsScaled)
        let (resultDenominator, o4) = denominator.multipliedReportingOverflow(by: lhsScale)
        guard !o1, !o2, !o3, !o4 else {
            throw FCPTimeError.overflow(
                operation: operation, lhs: fcpxmlString, rhs: other.fcpxmlString)
        }
        // The sum of two reduced fractions over an LCM can share a factor; reduce.
        return try FCPTime(numerator: resultNumerator, denominator: resultDenominator)
    }

    /// Exact negation. Throws `.overflow` only for `Int64.min` numerators.
    public func negated() throws(FCPTimeError) -> FCPTime {
        guard numerator != Int64.min else {
            throw FCPTimeError.overflow(operation: "negation", lhs: fcpxmlString, rhs: nil)
        }
        return FCPTime(reducedNumerator: -numerator, reducedDenominator: denominator)
    }

    /// Exact scalar multiple. Throws `.overflow` instead of wrapping.
    public func multiplied(by scalar: Int64) throws(FCPTimeError) -> FCPTime {
        let (result, overflow) = numerator.multipliedReportingOverflow(by: scalar)
        guard !overflow else {
            throw FCPTimeError.overflow(
                operation: "multiplication", lhs: fcpxmlString, rhs: "\(scalar)")
        }
        return try FCPTime(numerator: result, denominator: denominator)
    }

    // MARK: - Comparison

    /// Total order via 128-bit cross-multiplication: exact for every pair of
    /// values, never overflows, never throws.
    public static func < (lhs: FCPTime, rhs: FCPTime) -> Bool {
        // a/b < c/d  <=>  a*d < c*b  (b, d > 0). Full-width products are exact
        // signed 128-bit values represented as (high: Int64, low: UInt64).
        let left = lhs.numerator.multipliedFullWidth(by: rhs.denominator)
        let right = rhs.numerator.multipliedFullWidth(by: lhs.denominator)
        if left.high != right.high {
            return left.high < right.high
        }
        return left.low < right.low
    }

    // MARK: - Helpers

    /// Binary-safe greatest common divisor on magnitudes.
    static func gcd(_ a: UInt64, _ b: UInt64) -> UInt64 {
        var a = a
        var b = b
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return a
    }
}

// MARK: - Codable

extension FCPTime: Codable {
    /// Encodes as the canonical FCPXML string (readable golden files); decodes
    /// through the strict parser.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        do {
            try self.init(fcpxmlString: raw)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: error.description)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(fcpxmlString)
    }
}
