import Foundation

struct SubscriptionCandidate: Identifiable, Hashable {
    let id: UUID
    let name: String
    let amountMinor: Int
    let currencyCode: String
    let billingCycle: BillingCycle
    let confidence: Double
    var isDuplicate: Bool
    let detectedNextBillingDate: Date?

    enum ConfidenceTier { case strong, normal, dim }

    var confidenceTier: ConfidenceTier {
        if confidence >= SubscriptionDetector.strongThreshold { return .strong }
        if confidence >= SubscriptionDetector.dimThreshold    { return .normal }
        return .dim
    }

    var money: Money {
        Money(minorUnits: amountMinor, currencyCode: currencyCode)
    }

    init(
        id: UUID = UUID(),
        name: String,
        amountMinor: Int,
        currencyCode: String,
        billingCycle: BillingCycle,
        confidence: Double,
        isDuplicate: Bool = false,
        detectedNextBillingDate: Date? = nil
    ) {
        self.id                     = id
        self.name                   = name
        self.amountMinor            = amountMinor
        self.currencyCode           = currencyCode
        self.billingCycle           = billingCycle
        self.confidence             = min(1.0, max(0.0, confidence))
        self.isDuplicate            = isDuplicate
        self.detectedNextBillingDate = detectedNextBillingDate
    }
}
