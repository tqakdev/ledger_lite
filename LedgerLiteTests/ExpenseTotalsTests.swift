import Testing
import Foundation
@testable import LedgerLite

// MARK: - Helpers

private func expense(
    _ amountMinor: Int,
    _ currency: String,
    rate: Decimal = 1,
    home: String = "USD"
) -> Expense {
    Expense(
        amountMinor: amountMinor,
        currencyCode: currency,
        exchangeRateToHome: rate,
        homeCurrencyAtEntry: home,
        date: Date()
    )
}

// MARK: - Characterization of the canonical home-currency total

@Suite("Expense — totalInHomeCurrency")
struct ExpenseTotalsTests {

    @Test("same-currency expenses sum raw minor units")
    @MainActor
    func sameCurrencySum() {
        let expenses = [expense(1234, "USD"), expense(866, "USD")]
        #expect(expenses.totalInHomeCurrency("USD") == 2100)
    }

    @Test("foreign expense converts via its frozen rate")
    @MainActor
    func foreignConverts() {
        // €10.00 at 1.10 → $11.00
        let expenses = [expense(1000, "EUR", rate: Decimal(string: "1.10")!)]
        #expect(expenses.totalInHomeCurrency("USD") == 1100)
    }

    @Test("JPY expense (0-decimal) lands correctly in a 2-decimal home")
    @MainActor
    func zeroDecimalToTwoDecimal() {
        // ¥1500 at 0.0065 USD/JPY → $9.75
        let expenses = [expense(1500, "JPY", rate: Decimal(string: "0.0065")!)]
        #expect(expenses.totalInHomeCurrency("USD") == 975)
    }

    @Test("rounding happens once on the accumulated sum, not per row")
    @MainActor
    func singleFinalRounding() {
        // Three rows of €0.01 at rate 1.005 → each 1.005¢; per-row rounding would
        // give 3¢ (1+1+1); accumulate-then-round gives round(3.015) = 3¢ as well,
        // so distinguish with rate 1.4: per-row round(1.4)=1 → 3; final round(4.2)=4.
        let rate = Decimal(string: "1.4")!
        let expenses = [
            expense(1, "EUR", rate: rate),
            expense(1, "EUR", rate: rate),
            expense(1, "EUR", rate: rate),
        ]
        #expect(expenses.totalInHomeCurrency("USD") == 4)
    }

    @Test("mixed same-currency and foreign rows combine")
    @MainActor
    func mixedRows() {
        let expenses = [
            expense(5000, "USD"),                                  // $50.00
            expense(1000, "EUR", rate: Decimal(string: "1.10")!),  // $11.00
        ]
        #expect(expenses.totalInHomeCurrency("USD") == 6100)
    }

    @Test("empty list totals zero")
    @MainActor
    func emptyIsZero() {
        #expect([Expense]().totalInHomeCurrency("USD") == 0)
    }
}
