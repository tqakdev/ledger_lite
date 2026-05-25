import Foundation

extension Decimal {
    /// Rounds using `NSDecimalRound` — operates on `Decimal` directly, no `NSDecimalNumber` round-trip.
    func rounded(scale: Int, roundingMode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var result = Decimal()
        var copy = self
        NSDecimalRound(&result, &copy, scale, roundingMode)
        return result
    }

    /// Parses a decimal string using en_US_POSIX locale (dot as decimal separator).
    /// Validates the full string before parsing — rejects partial parses such as
    /// "1.234.56" (→ .zero) and "1,234.56" (→ .zero). Deterministic across all locales.
    /// Intended for API response values and persisted rate strings; not for user-typed input.
    init(safeString string: String) {
        // Anchored regex: optional minus, one-or-more digits, optional dot + digits.
        // Rejects anything with commas, multiple dots, trailing garbage, or empty input.
        guard string.range(of: #"^-?[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil else {
            self = .zero
            return
        }
        self = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) ?? .zero
    }

    /// Returns 10^exponent using Decimal arithmetic.
    /// Exponent is always 0, 2, or 3 for minor-unit conversion in this app.
    static func powerOfTen(_ exponent: Int) -> Decimal {
        guard exponent > 0 else { return 1 }
        return (0..<exponent).reduce(Decimal(1)) { acc, _ in acc * 10 }
    }
}
