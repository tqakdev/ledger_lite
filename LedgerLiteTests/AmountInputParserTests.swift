import Testing
import Foundation
@testable import LedgerLite

// MARK: - Helpers

private func usdParser(locale: Locale = Locale(identifier: "en_US")) -> AmountInputParser {
    AmountInputParser(currencyCode: "USD", locale: locale)
}
private func jpyParser() -> AmountInputParser { AmountInputParser(currencyCode: "JPY", locale: Locale(identifier: "en_US")) }
private func bhdParser() -> AmountInputParser { AmountInputParser(currencyCode: "BHD", locale: Locale(identifier: "en_US")) }

// MARK: - USD — parse

@Suite("AmountInputParser — USD parse")
struct AmountInputParserUSDTests {

    @Test("standard two-decimal input")
    func standard() {
        let (d, m) = usdParser().parse("12.34")
        #expect(d == "12.34")
        #expect(m == 1234)
    }

    @Test("one decimal place → trailing zero implied")
    func oneDecimal() {
        let (d, m) = usdParser().parse("12.3")
        #expect(d == "12.3")
        #expect(m == 1230)
    }

    @Test("integer only → two implied zeros")
    func integerOnly() {
        let (d, m) = usdParser().parse("12")
        #expect(d == "12")
        #expect(m == 1200)
    }

    @Test("empty string → zero")
    func empty() {
        let (d, m) = usdParser().parse("")
        #expect(d == "")
        #expect(m == 0)
    }

    @Test("EU locale: comma separator → 1234 minor units")
    func euLocale() {
        let parser = AmountInputParser(currencyCode: "USD", locale: Locale(identifier: "fr_FR"))
        let (d, m) = parser.parse("12,34")
        #expect(d == "12,34")
        #expect(m == 1234)
    }

    @Test("strips leading and trailing non-digit characters")
    func stripAlpha() {
        let (d, m) = usdParser().parse("abc12.34xyz")
        #expect(d == "12.34")
        #expect(m == 1234)
    }

    @Test("caps fractional part at 2 digits")
    func capFractional() {
        let (d, m) = usdParser().parse("12.345")
        #expect(d == "12.34")
        #expect(m == 1234)
    }

    // Defined behaviour: merge fractional digits from all occurrences after the first separator.
    // "1.2.3" → integerPart "1", fractionalAll "23" → "1.23" / 123 minor units.
    @Test("double separator: merge trailing digits — '1.2.3' → '1.23'")
    func doubleDecimal() {
        let (d, m) = usdParser().parse("1.2.3")
        #expect(d == "1.23")
        #expect(m == 123)
    }

    @Test("leading separator → '$0.50'")
    func leadingSeparator() {
        let (d, m) = usdParser().parse(".5")
        #expect(d == ".5")
        #expect(m == 50)
    }

    @Test("trailing separator with no fractional digits")
    func trailingSeparator() {
        let (d, m) = usdParser().parse("1.")
        #expect(d == "1.")
        #expect(m == 100)
    }

    @Test("zero")
    func zero() {
        let (d, m) = usdParser().parse("0")
        #expect(d == "0")
        #expect(m == 0)
    }

    @Test("negative sign stripped — positive only at entry")
    func negativeStripped() {
        // Phase 3.6 decision: negatives are disallowed at entry.
        // The minus sign is not a digit or decimal separator, so it is stripped.
        let (d, m) = usdParser().parse("-12.34")
        #expect(d == "12.34")
        #expect(m == 1234)
    }
}

// MARK: - JPY — parse

@Suite("AmountInputParser — JPY parse")
struct AmountInputParserJPYTests {

    @Test("integer → same value (no minor-unit division)")
    func integer() {
        let (d, m) = jpyParser().parse("12")
        #expect(d == "12")
        #expect(m == 12)
    }

    @Test("decimal input stripped — JPY has 0 decimal places")
    func decimalStripped() {
        let (d, m) = jpyParser().parse("12.5")
        #expect(d == "12")
        #expect(m == 12)
    }
}

// MARK: - BHD — parse (3 decimal places)

@Suite("AmountInputParser — BHD parse")
struct AmountInputParserBHDTests {

    @Test("exactly 3 fractional digits → 12345 minor units")
    func threePlaces() {
        let (d, m) = bhdParser().parse("12.345")
        #expect(d == "12.345")
        #expect(m == 12345)
    }

    @Test("4 fractional digits capped to 3")
    func capToThree() {
        let (d, m) = bhdParser().parse("12.3456")
        #expect(d == "12.345")
        #expect(m == 12345)
    }
}

// MARK: - Overflow / cap safety

@Suite("AmountInputParser — overflow safety")
struct AmountInputParserOverflowTests {

    // The numpad appends digits with no length cap, so `parse` can receive an
    // arbitrarily long string. Scaling such an integer to minor units used to
    // overflow Int and trap; it must clamp to the cap instead.
    @Test("17-digit integer (Int-parseable but overflows ×100) clamps, not crash")
    func seventeenDigitsClamps() {
        let (_, m) = usdParser().parse(String(repeating: "9", count: 17))
        #expect(m == 999_999_999)
    }

    @Test("over-long integer (beyond Int range) clamps, not crash")
    func beyondIntRangeClamps() {
        let (_, m) = usdParser().parse(String(repeating: "9", count: 25))
        #expect(m == 999_999_999)
    }

    @Test("amount above the cap is clamped to 999_999_999")
    func aboveCapClamps() {
        let (_, m) = usdParser().parse("12345678.99")  // 1_234_567_899 minor > cap
        #expect(m == 999_999_999)
    }
}

// MARK: - format (edit-mode round-trip)

@Suite("AmountInputParser — format (edit-mode)")
struct AmountInputParserFormatTests {

    @Test("USD 1234 → '12.34'")
    func usd() {
        #expect(usdParser().format(minorUnits: 1234) == "12.34")
    }

    @Test("USD 100 → '1.00'")
    func usdRoundNumber() {
        #expect(usdParser().format(minorUnits: 100) == "1.00")
    }

    @Test("USD 5 → '0.05'")
    func usdSmall() {
        #expect(usdParser().format(minorUnits: 5) == "0.05")
    }

    @Test("zero → empty string (field shows placeholder instead)")
    func zero() {
        #expect(usdParser().format(minorUnits: 0) == "")
    }

    @Test("JPY 12 → '12'")
    func jpy() {
        #expect(jpyParser().format(minorUnits: 12) == "12")
    }

    @Test("BHD 12345 → '12.345'")
    func bhd() {
        #expect(bhdParser().format(minorUnits: 12345) == "12.345")
    }

    @Test("parse then format round-trips correctly for USD")
    func roundTrip() {
        let parser = usdParser()
        let (_, minor) = parser.parse("42.50")
        #expect(parser.format(minorUnits: minor) == "42.50")
    }
}
