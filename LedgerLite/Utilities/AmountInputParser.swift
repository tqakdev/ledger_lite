import Foundation

/// Converts a user-typed decimal string to minor-unit integers and a sanitized display string.
///
/// This is a pure value type with no side effects — pass it any raw TextField string and get back
/// what to display and what to store.
struct AmountInputParser {
    let currencyCode: String
    let locale: Locale

    private var places: Int { Money.decimals(for: currencyCode) }

    /// The locale's decimal separator character (e.g. "." in en_US, "," in fr_FR).
    private var sep: Character { (locale.decimalSeparator ?? ".").first ?? "." }

    // MARK: - Public API

    /// Returns `(sanitizedDisplay, minorUnits)`.
    ///
    /// Rules applied in order:
    /// 1. All characters that are not ASCII digits or the locale decimal separator are stripped.
    /// 2. The first separator occurrence is honored. Subsequent separators are removed, but
    ///    their trailing digits are merged into the fractional part — "1.2.3" → "1.23".
    /// 3. Fractional digits are capped at `Money.decimals(for: currencyCode)`.
    ///    For 0-decimal currencies (JPY, KRW) the separator is stripped entirely.
    /// 4. Minor units are capped at 999_999_999.
    /// 5. Negative input is rejected — all input is treated as a positive amount.
    func parse(_ raw: String) -> (display: String, minorUnits: Int) {
        let sepChar = sep
        let cleaned = String(raw.filter { ($0 >= "0" && $0 <= "9") || $0 == sepChar })

        guard !cleaned.isEmpty else { return ("", 0) }

        let components = cleaned.components(separatedBy: String(sepChar))
        let integerPart = components[0]
        let hasSeparator = cleaned.contains(sepChar)

        // Merge digits from every component after the first separator
        let fractionalAll = components.count > 1 ? components.dropFirst().joined() : ""
        let fractionalCapped = String(fractionalAll.prefix(places))

        // Build display — strip separator for 0-decimal currencies
        let display: String
        if hasSeparator && places > 0 {
            display = integerPart + String(sepChar) + fractionalCapped
        } else {
            display = integerPart
        }

        // Compute minor units. The numpad appends digits without a length cap, so
        // `integerPart` can be arbitrarily long: a value too large for Int, or one
        // that overflows when scaled by `multiplier`, must clamp to the cap below
        // rather than trap. `parse` is a pure function and must never crash on input.
        let intVal = Int(integerPart.isEmpty ? "0" : integerPart) ?? Int.max
        let multiplier = pow10(places)

        let minorUnits: Int
        if places == 0 {
            minorUnits = intVal
        } else {
            // Pad fractional part on the right with zeros: "3" → "30" for 2-decimal currencies
            let fracPadded = fractionalCapped.padding(toLength: places, withPad: "0", startingAt: 0)
            let fracVal = Int(fracPadded) ?? 0
            let (scaled, scaledOverflow) = intVal.multipliedReportingOverflow(by: multiplier)
            if scaledOverflow {
                minorUnits = Int.max
            } else {
                let (sum, sumOverflow) = scaled.addingReportingOverflow(fracVal)
                minorUnits = sumOverflow ? Int.max : sum
            }
        }

        return (display, min(minorUnits, 999_999_999))
    }

    /// Converts stored minor units back to a display string for edit-mode initialisation.
    func format(minorUnits: Int) -> String {
        guard minorUnits > 0 else { return "" }
        let places = self.places
        if places == 0 { return String(minorUnits) }
        let multiplier = pow10(places)
        let intPart = minorUnits / multiplier
        let fracPart = minorUnits % multiplier
        let fracStr = String(format: "%0\(places)d", fracPart)
        return "\(intPart)\(sep)\(fracStr)"
    }

    // MARK: - Private

    private func pow10(_ exp: Int) -> Int {
        guard exp > 0 else { return 1 }
        return (0..<exp).reduce(1) { acc, _ in acc * 10 }
    }
}
