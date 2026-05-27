import Testing
import Foundation
@testable import LedgerLite

// MARK: - Amount extraction

@Suite("SubscriptionDetector — amount extraction")
struct AmountExtractionTests {

    @Test("dollar symbol → USD minor units")
    func dollarSymbol() {
        let result = SubscriptionDetector.extractAmount(from: "$9.99 charged monthly subscription")
        #expect(result?.minorUnits == 999)
        #expect(result?.currencyCode == "USD")
    }

    @Test("euro symbol → EUR minor units")
    func euroSymbol() {
        let result = SubscriptionDetector.extractAmount(from: "€12.99 monthly membership")
        #expect(result?.minorUnits == 1299)
        #expect(result?.currencyCode == "EUR")
    }

    @Test("pound symbol → GBP minor units")
    func poundSymbol() {
        let result = SubscriptionDetector.extractAmount(from: "£6.99/month plan")
        #expect(result?.minorUnits == 699)
        #expect(result?.currencyCode == "GBP")
    }

    @Test("ISO code prefix — USD 9.99")
    func isoPrefix() {
        let result = SubscriptionDetector.extractAmount(from: "USD 9.99 per month")
        #expect(result?.minorUnits == 999)
        #expect(result?.currencyCode == "USD")
    }

    @Test("ISO code suffix — 14.99 EUR")
    func isoSuffix() {
        let result = SubscriptionDetector.extractAmount(from: "14.99 EUR subscription billed monthly")
        #expect(result?.minorUnits == 1499)
        #expect(result?.currencyCode == "EUR")
    }

    @Test("European comma decimal — €9,99")
    func commaDecimal() {
        let result = SubscriptionDetector.extractAmount(from: "€9,99 monthly subscription")
        #expect(result?.minorUnits == 999)
        #expect(result?.currencyCode == "EUR")
    }

    @Test("JPY — no decimal places — ¥1500")
    func jpyNoDecimal() {
        let result = SubscriptionDetector.extractAmount(from: "¥1500 monthly subscription")
        #expect(result?.minorUnits == 1500)
        #expect(result?.currencyCode == "JPY")
    }

    @Test("unknown ISO code → no match (returns nil)")
    func unknownCurrencyFallsBack() {
        // XYZ is not in supportedCurrencies; no symbol present → nil
        let result = SubscriptionDetector.extractAmount(from: "XYZ 9.99 subscription monthly")
        #expect(result == nil)
    }

    @Test("amount out of range still extracted; lower confidence than in-range")
    func outOfRangeAmountExtractedWithLowerConfidence() {
        // $999.99 = 99999 minor units, outside ≤50000 → no plausible-range bonus
        let overpriced = SubscriptionDetector.detect(in: "Netflix subscription $999.99 billed monthly")
        #expect(!overpriced.isEmpty, "High-confidence known service still returns a candidate")

        let inRange = SubscriptionDetector.detect(in: "Netflix subscription $15.49 billed monthly")
        #expect(!inRange.isEmpty)
        #expect(overpriced.first!.confidence < inRange.first!.confidence,
                "In-range amount earns the +0.15 plausible-range bonus; out-of-range does not")
    }

    @Test("empty string → no candidates")
    func emptyStringReturnsNone() {
        #expect(SubscriptionDetector.detect(in: "").isEmpty)
    }
}

// MARK: - Billing cycle extraction

@Suite("SubscriptionDetector — billing cycle extraction")
struct BillingCycleExtractionTests {

    @Test("'monthly plan' → .monthly")
    func monthlyPlan() {
        #expect(SubscriptionDetector.extractBillingCycle(from: "monthly plan") == .monthly)
    }

    @Test("'annual subscription' → .yearly")
    func annualSubscription() {
        #expect(SubscriptionDetector.extractBillingCycle(from: "annual subscription") == .yearly)
    }

    @Test("'billed yearly' → .yearly")
    func billedYearly() {
        #expect(SubscriptionDetector.extractBillingCycle(from: "billed yearly") == .yearly)
    }

    @Test("'every 14 days' → .customDays(14)")
    func every14Days() {
        #expect(SubscriptionDetector.extractBillingCycle(from: "charged every 14 days") == .customDays(14))
    }

    @Test("'every 2 weeks' → .customDays(14)")
    func every2Weeks() {
        #expect(SubscriptionDetector.extractBillingCycle(from: "renews every 2 weeks") == .customDays(14))
    }

    @Test("no keyword → default .monthly")
    func noKeywordDefaultsMonthly() {
        #expect(SubscriptionDetector.extractBillingCycle(from: "Acme renewal $9.99") == .monthly)
    }
}

// MARK: - Known service matching

@Suite("SubscriptionDetector — known service matching")
struct KnownServiceMatchingTests {

    @Test("Netflix receipt text → name = Netflix")
    func netflixReceipt() {
        let text = "Your Netflix subscription will renew on Jan 15 for $15.49 billed monthly."
        let candidates = SubscriptionDetector.detect(in: text)
        #expect(candidates.first?.name == "Netflix")
    }

    @Test("Spotify confirmation snippet → name = Spotify")
    func spotifyConfirmation() {
        let text = "Spotify Premium — $9.99/month subscription renewal confirmed."
        let candidates = SubscriptionDetector.detect(in: text)
        #expect(candidates.first?.name == "Spotify")
    }

    @Test("unknown service falls back to name extraction")
    func unknownServiceNameExtraction() {
        let text = "Your Acme Pro subscription: $29.99/month billed monthly."
        let candidates = SubscriptionDetector.detect(in: text)
        // Should produce a candidate with the extracted name, not nil
        #expect(!candidates.isEmpty)
        #expect(candidates.first?.name != nil)
    }

    @Test("known service match is case-insensitive")
    func caseInsensitiveMatch() {
        let text = "NETFLIX renewal charged $15.49 monthly subscription"
        let candidates = SubscriptionDetector.detect(in: text)
        #expect(candidates.first?.name == "Netflix")
    }
}

// MARK: - Confidence scoring

@Suite("SubscriptionDetector — confidence scoring")
struct ConfidenceScoringTests {

    @Test("known service + cycle keyword → confidence ≥ strongThreshold")
    func knownServiceWithCycleKeyword() {
        let text = "Netflix $15.49 monthly subscription"
        let candidates = SubscriptionDetector.detect(in: text)
        #expect((candidates.first?.confidence ?? 0) >= SubscriptionDetector.strongThreshold)
    }

    @Test("amount only (no service, no keywords) → confidence ≈ 0.35–0.55")
    func amountOnlyLowConfidence() {
        // "Service" is a generic name → no non-generic bonus; "Service $9.99" has base + range only
        let candidates = SubscriptionDetector.detect(in: "Service $9.99")
        let confidence = candidates.first?.confidence ?? 0
        #expect(confidence > 0, "Should be above noise threshold")
        #expect(confidence <= 0.55, "Should not exceed amount-only ceiling")
    }

    @Test("noise text scored below noiseThreshold is filtered out")
    func noiseTextIsFiltered() {
        // Out-of-range amount + generic name → 0.35 base only → below 0.40 threshold
        let candidates = SubscriptionDetector.detect(in: "Service $999.99")
        #expect(candidates.isEmpty)
    }

    @Test("subscription keyword boosts confidence")
    func subscriptionKeywordBoostsScore() {
        let without = SubscriptionDetector.detect(in: "Acme $9.99")
        let with    = SubscriptionDetector.detect(in: "Acme $9.99 subscription")
        #expect((with.first?.confidence ?? 0) > (without.first?.confidence ?? 0))
    }

    @Test("full realistic email → strong confidence")
    func realisticEmailStrongConfidence() {
        let email = """
        Hi there,
        Your Netflix subscription will automatically renew on January 15, 2026.
        Amount: $15.49
        Billing: monthly
        Thank you for your subscription.
        """
        let candidates = SubscriptionDetector.detect(in: email)
        #expect((candidates.first?.confidence ?? 0) >= SubscriptionDetector.strongThreshold)
    }
}

// MARK: - Deduplication

@Suite("SubscriptionDetector — deduplication")
struct DeduplicationTests {

    @Test("same service mentioned twice → one candidate")
    func sameNameDeduplicates() {
        let text = """
        Netflix $15.49 monthly subscription
        Your Netflix membership billed monthly for $15.49
        """
        let candidates = SubscriptionDetector.detect(in: text)
        let netflixCount = candidates.filter { $0.name == "Netflix" }.count
        #expect(netflixCount == 1)
    }

    @Test("two different services → two candidates")
    func differentNamesKeptSeparate() {
        let text = """
        Netflix $15.49 monthly subscription
        Spotify $9.99 monthly subscription
        """
        let candidates = SubscriptionDetector.detect(in: text)
        #expect(candidates.count == 2)
        #expect(candidates.contains(where: { $0.name == "Netflix" }))
        #expect(candidates.contains(where: { $0.name == "Spotify" }))
    }
}
