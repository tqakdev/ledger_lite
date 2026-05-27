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

extension Array where Element == Expense {
    /// Converts each expense to home-currency minor units and sums them.
    /// Accumulates as Decimal before a single final rounding to avoid per-row drift.
    func totalInHomeCurrency(_ currencyCode: String) -> Int {
        let places = Money.decimals(for: currencyCode)
        var sum = Decimal(0)
        for expense in self {
            if expense.currencyCode == expense.homeCurrencyAtEntry {
                sum += Decimal(expense.amountMinor)
            } else {
                sum += expense.money.decimalValue * expense.exchangeRateToHome * Decimal.powerOfTen(places)
            }
        }
        return NSDecimalNumber(decimal: sum.rounded(scale: 0)).intValue
    }
}
