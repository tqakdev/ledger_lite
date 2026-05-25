import Foundation

// MARK: - MoneyError

enum MoneyError: Error, Equatable {
    case currencyMismatch(String, String)
    case emptySumArray
}

// MARK: - Money

/// Immutable value type for all monetary amounts.
/// Always stored as minor units (Int) + ISO 4217 currency code.
/// Never use Double for money; all math goes through this type.
struct Money: Hashable, Codable {
    let minorUnits: Int
    let currencyCode: String

    // MARK: ISO 4217 minor-unit digit table

    /// Number of digits after the decimal point per ISO 4217.
    /// Currencies not listed default to 2.
    static let minorUnitDigits: [String: Int] = [
        // 0 decimal places
        "JPY": 0, "KRW": 0, "VND": 0,
        // 3 decimal places
        "BHD": 3, "KWD": 3, "OMR": 3, "JOD": 3, "TND": 3,
    ]

    static func decimals(for code: String) -> Int {
        minorUnitDigits[code] ?? 2
    }

    // MARK: Computed

    /// The monetary value as a Decimal, respecting the currency's decimal places.
    var decimalValue: Decimal {
        let digits = Self.decimals(for: currencyCode)
        guard digits > 0 else { return Decimal(minorUnits) }
        return Decimal(minorUnits) / Decimal.powerOfTen(digits)
    }

    // MARK: Formatting

    /// Formats the amount as a currency string.
    /// Always pass an explicit locale in tests so results are locale-independent.
    func formatted(locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currencyCode
        let digits = Self.decimals(for: currencyCode)
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: decimalValue as NSDecimalNumber)
            ?? "\(currencyCode) \(decimalValue)"
    }

    // MARK: Conversion

    /// Returns a new Money in `targetCode` at the given exchange rate.
    /// `rate` is: 1 unit of self.currencyCode = `rate` units of `targetCode`.
    /// All arithmetic is Decimal — never Double.
    func converted(to targetCode: String, rate: Decimal) -> Money {
        let targetDigits = Self.decimals(for: targetCode)
        let raw = decimalValue * rate
        let rounded = raw.rounded(scale: targetDigits)
        let multiplier = Decimal.powerOfTen(targetDigits)
        let minorUnitsDecimal = (rounded * multiplier).rounded(scale: 0)
        return Money(
            minorUnits: (minorUnitsDecimal as NSDecimalNumber).intValue,
            currencyCode: targetCode
        )
    }

    // MARK: Arithmetic

    /// Returns the sum of `self` and `other`.
    /// Throws if the currencies differ — callers must convert first.
    func adding(_ other: Money) throws -> Money {
        guard currencyCode == other.currencyCode else {
            throw MoneyError.currencyMismatch(currencyCode, other.currencyCode)
        }
        return Money(minorUnits: minorUnits + other.minorUnits, currencyCode: currencyCode)
    }

    /// Returns the sum of an array of same-currency Money values.
    /// Throws `emptySumArray` if `monies` is empty.
    /// Throws `currencyMismatch` if the array contains mixed currencies.
    static func sum(_ monies: [Money]) throws -> Money {
        guard let first = monies.first else { throw MoneyError.emptySumArray }
        return try monies.dropFirst().reduce(first) { try $0.adding($1) }
    }
}
