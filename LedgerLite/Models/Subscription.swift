import Foundation
import SwiftData

@Model
final class Subscription {
    // No @Attribute(.unique) — CloudKit-compatible; uniqueness enforced in repository.
    var id: UUID = UUID()
    var name: String = ""
    var amountMinor: Int = 0
    var currencyCode: String = "USD"
    var billingCycleRaw: String = BillingCycle.monthly.rawValue
    var nextBillingDate: Date = Date()
    var startedOn: Date = Date()
    var statusRaw: String = SubscriptionStatus.active.rawValue
    var autoDetected: Bool = false
    var notes: String?

    var category: Category?

    // deleteRule: .nullify — deleting a Subscription keeps its historical Expenses,
    // it just clears their subscription back-reference.
    @Relationship(deleteRule: .nullify)
    var generatedExpenses: [Expense] = []

    // MARK: Computed bridges

    var billingCycle: BillingCycle {
        get { BillingCycle(rawValue: billingCycleRaw) ?? .monthly }
        set { billingCycleRaw = newValue.rawValue }
    }

    var status: SubscriptionStatus {
        get { SubscriptionStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var money: Money { Money(minorUnits: amountMinor, currencyCode: currencyCode) }

    // MARK: Monthly equivalent

    /// Monthly equivalent in minor units for the "true monthly cost" card.
    /// Uses billing cycle's monthly factor. Pure integer math — no Double.
    func monthlyEquivalentMinorUnits() -> Int {
        let factor = billingCycle.monthlyFactor
        var product = Decimal(amountMinor) * factor
        var result = Decimal()
        NSDecimalRound(&result, &product, 0, .plain)
        return (result as NSDecimalNumber).intValue
    }

    // MARK: Init

    init(
        id: UUID = UUID(),
        name: String,
        amountMinor: Int,
        currencyCode: String,
        billingCycle: BillingCycle = .monthly,
        nextBillingDate: Date,
        startedOn: Date = Date(),
        status: SubscriptionStatus = .active,
        autoDetected: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.billingCycleRaw = billingCycle.rawValue
        self.nextBillingDate = nextBillingDate
        self.startedOn = startedOn
        self.statusRaw = status.rawValue
        self.autoDetected = autoDetected
        self.notes = notes
    }
}
