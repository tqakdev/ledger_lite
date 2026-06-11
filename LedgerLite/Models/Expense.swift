import Foundation
import SwiftData

@Model
final class Expense {
    // No @Attribute(.unique) — CloudKit-compatible; uniqueness enforced in repository.
    var id: UUID = UUID()
    var amountMinor: Int = 0
    var currencyCode: String = "USD"
    var exchangeRateToHome: Decimal = 1        // frozen at entry; never changes after save
    var homeCurrencyAtEntry: String = "USD"    // snapshot of home currency at time of entry
    var date: Date = Date()
    var note: String?
    var merchant: String?
    var sourceRaw: String = ExpenseSource.manual.rawValue
    /// True when saved offline without a live rate; cleared when rates are refreshed.
    var needsRateRefresh: Bool = false

    var category: Category?

    @Relationship(deleteRule: .nullify, inverse: \Subscription.generatedExpenses)
    var subscription: Subscription?

    // MARK: Computed bridges

    var source: ExpenseSource {
        get { ExpenseSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var money: Money { Money(minorUnits: amountMinor, currencyCode: currencyCode) }

    // MARK: Init

    init(
        id: UUID = UUID(),
        amountMinor: Int,
        currencyCode: String,
        exchangeRateToHome: Decimal = 1,
        homeCurrencyAtEntry: String,
        date: Date = Date(),
        note: String? = nil,
        merchant: String? = nil,
        source: ExpenseSource = .manual,
        needsRateRefresh: Bool = false
    ) {
        self.id = id
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.exchangeRateToHome = exchangeRateToHome
        self.homeCurrencyAtEntry = homeCurrencyAtEntry
        self.date = date
        self.note = note
        self.merchant = merchant
        self.sourceRaw = source.rawValue
        self.needsRateRefresh = needsRateRefresh
    }
}

extension Expense {
    /// This expense's value in home-currency minor units, as an unrounded Decimal.
    ///
    /// The single source of truth for home-currency conversion — every aggregation
    /// (Today total, daily average, Insights, budgets, widget) must go through this,
    /// accumulate Decimals, and round once at the end. `homePlaces` is
    /// `Money.decimals(for:)` of the home currency the caller is summing into.
    func homeMinorDecimal(homePlaces: Int) -> Decimal {
        if currencyCode == homeCurrencyAtEntry {
            return Decimal(amountMinor)
        }
        return money.decimalValue * exchangeRateToHome * Decimal.powerOfTen(homePlaces)
    }
}

extension Array where Element == Expense {
    /// Converts each expense to home-currency minor units and sums them.
    /// Accumulates as Decimal before a single final rounding to avoid per-row drift.
    func totalInHomeCurrency(_ currencyCode: String) -> Int {
        let places = Money.decimals(for: currencyCode)
        let sum = reduce(Decimal(0)) { $0 + $1.homeMinorDecimal(homePlaces: places) }
        return NSDecimalNumber(decimal: sum.rounded(scale: 0)).intValue
    }
}
