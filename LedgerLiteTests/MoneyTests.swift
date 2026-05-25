import Testing
import Foundation
@testable import LedgerLite

// MARK: - Money

@Suite("Money — formatting")
struct MoneyFormattingTests {

    @Test("USD 500 minor units → $5.00 (en_US)")
    func usdFormatting() {
        let money = Money(minorUnits: 500, currencyCode: "USD")
        #expect(money.formatted(locale: Locale(identifier: "en_US")) == "$5.00")
    }

    @Test("JPY 500 minor units → ¥500, no decimal point (en_US)")
    func jpyFormatting() {
        let money = Money(minorUnits: 500, currencyCode: "JPY")
        let formatted = money.formatted(locale: Locale(identifier: "en_US"))
        #expect(formatted.contains("500"))
        #expect(!formatted.contains("."))
    }

    @Test("BHD 1500 minor units → 1.500 (3 decimal places)")
    func bhdFormatting() {
        let money = Money(minorUnits: 1500, currencyCode: "BHD")
        let formatted = money.formatted(locale: Locale(identifier: "en_US"))
        #expect(formatted.contains("1.500"))
    }

    @Test("Negative USD formats correctly for refunds")
    func negativeUsdFormatting() {
        let refund = Money(minorUnits: -1000, currencyCode: "USD")
        let formatted = refund.formatted(locale: Locale(identifier: "en_US"))
        // NumberFormatter uses either minus sign or parentheses for negatives
        let hasNegativeIndicator = formatted.contains("-") || formatted.contains("(")
        #expect(hasNegativeIndicator)
        #expect(formatted.contains("10.00"))
    }
}

@Suite("Money — decimalValue")
struct MoneyDecimalValueTests {

    @Test("USD: minorUnits / 100")
    func usdDecimalValue() {
        #expect(Money(minorUnits: 123, currencyCode: "USD").decimalValue == Decimal(string: "1.23")!)
    }

    @Test("JPY: minorUnits directly (0 decimal places)")
    func jpyDecimalValue() {
        #expect(Money(minorUnits: 500, currencyCode: "JPY").decimalValue == Decimal(500))
    }

    @Test("BHD: minorUnits / 1000 (3 decimal places)")
    func bhdDecimalValue() {
        #expect(Money(minorUnits: 1500, currencyCode: "BHD").decimalValue == Decimal(string: "1.500")!)
    }
}

@Suite("Money — conversion")
struct MoneyConversionTests {

    @Test("USD → EUR: $10.00 × 0.92 = €9.20 = 920 minor units")
    func usdToEur() {
        let usd = Money(minorUnits: 1000, currencyCode: "USD")
        let eur = usd.converted(to: "EUR", rate: Decimal(string: "0.92")!)
        #expect(eur.currencyCode == "EUR")
        #expect(eur.minorUnits == 920)
    }

    @Test("USD → JPY: $1.00 × 150 = ¥150 (rounded to 0 decimal places)")
    func usdToJpy() {
        let usd = Money(minorUnits: 100, currencyCode: "USD")
        let jpy = usd.converted(to: "JPY", rate: Decimal(150))
        #expect(jpy.currencyCode == "JPY")
        #expect(jpy.minorUnits == 150)
    }

    @Test("Round-trip USD→EUR→USD stays within 1 minor unit")
    func roundTrip() {
        let original = Money(minorUnits: 1000, currencyCode: "USD")
        let rate = Decimal(string: "0.9213")!
        let converted = original.converted(to: "EUR", rate: rate)
        let inverseRate = Decimal(1) / rate
        let roundTripped = converted.converted(to: "USD", rate: inverseRate)
        #expect(abs(roundTripped.minorUnits - original.minorUnits) <= 1)
    }
}

@Suite("Money — arithmetic")
struct MoneyArithmeticTests {

    @Test("adding same currency returns sum")
    func addingSameCurrency() throws {
        let a = Money(minorUnits: 500, currencyCode: "USD")
        let b = Money(minorUnits: 300, currencyCode: "USD")
        let result = try a.adding(b)
        #expect(result.minorUnits == 800)
        #expect(result.currencyCode == "USD")
    }

    @Test("adding different currencies throws currencyMismatch")
    func addingDifferentCurrencies() {
        let a = Money(minorUnits: 500, currencyCode: "USD")
        let b = Money(minorUnits: 500, currencyCode: "EUR")
        #expect(throws: MoneyError.currencyMismatch("USD", "EUR")) {
            try a.adding(b)
        }
    }

    @Test("sum of empty array throws emptySumArray")
    func sumEmpty() {
        #expect(throws: MoneyError.emptySumArray) {
            try Money.sum([])
        }
    }

    @Test("sum of same-currency array")
    func sumSameCurrency() throws {
        let monies = [
            Money(minorUnits: 100, currencyCode: "USD"),
            Money(minorUnits: 200, currencyCode: "USD"),
            Money(minorUnits: 300, currencyCode: "USD"),
        ]
        #expect(try Money.sum(monies).minorUnits == 600)
    }

    @Test("sum of mixed currencies throws")
    func sumMixedCurrencies() {
        let monies = [
            Money(minorUnits: 100, currencyCode: "USD"),
            Money(minorUnits: 100, currencyCode: "EUR"),
        ]
        #expect(throws: MoneyError.self) {
            try Money.sum(monies)
        }
    }
}

// MARK: - BillingCycle

@Suite("BillingCycle — round-trip")
struct BillingCycleRoundTripTests {

    @Test("weekly / monthly / yearly round-trip through rawValue")
    func standardCases() {
        for cycle: BillingCycle in [.weekly, .monthly, .yearly] {
            #expect(BillingCycle(rawValue: cycle.rawValue) == cycle)
        }
    }

    @Test("customDays(30) rawValue is 'customDays:30' and round-trips")
    func customDaysRoundTrip() {
        let cycle = BillingCycle.customDays(30)
        #expect(cycle.rawValue == "customDays:30")
        #expect(BillingCycle(rawValue: "customDays:30") == cycle)
    }
}

@Suite("BillingCycle — invalid raw values")
struct BillingCycleValidationTests {

    @Test("customDays:0 → nil (zero-day cycle is nonsense)")
    func zeroDays() { #expect(BillingCycle(rawValue: "customDays:0") == nil) }

    @Test("customDays:-5 → nil (negative cycle)")
    func negativeDays() { #expect(BillingCycle(rawValue: "customDays:-5") == nil) }

    @Test("customDays: → nil (empty number)")
    func emptyNumber() { #expect(BillingCycle(rawValue: "customDays:") == nil) }

    @Test("customDays:abc → nil (non-numeric)")
    func nonNumeric() { #expect(BillingCycle(rawValue: "customDays:abc") == nil) }

    @Test("customDays:30:extra → nil (trailing content)")
    func trailingContent() { #expect(BillingCycle(rawValue: "customDays:30:extra") == nil) }

    @Test("CustomDays:30 → nil (wrong case)")
    func wrongCase() { #expect(BillingCycle(rawValue: "CustomDays:30") == nil) }

    @Test("Weekly → nil (capitalized)")
    func capitalizedWeekly() { #expect(BillingCycle(rawValue: "Weekly") == nil) }

    @Test("empty string → nil")
    func emptyString() { #expect(BillingCycle(rawValue: "") == nil) }

    @Test("unknown string → nil")
    func unknownString() { #expect(BillingCycle(rawValue: "fortnightly") == nil) }
}

// MARK: - Decimal+Extensions

@Suite("Decimal safeString init")
struct DecimalSafeStringTests {

    @Test("valid decimal string parses correctly")
    func validString() {
        #expect(Decimal(safeString: "1.23") == Decimal(string: "1.23", locale: Locale(identifier: "en_US_POSIX"))!)
    }

    @Test("empty string → .zero")
    func emptyString() { #expect(Decimal(safeString: "") == .zero) }

    @Test("non-numeric string → .zero")
    func nonNumeric() { #expect(Decimal(safeString: "abc") == .zero) }

    @Test("malformed double-dot string → .zero")
    func malformedDecimal() { #expect(Decimal(safeString: "1.234.56") == .zero) }

    @Test("locale-formatted comma string → .zero (POSIX locale rejects thousands separators)")
    func commaSeparated() { #expect(Decimal(safeString: "1,234.56") == .zero) }
}
