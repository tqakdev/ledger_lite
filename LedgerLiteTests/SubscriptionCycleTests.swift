import Testing
import Foundation
import SwiftData
@testable import LedgerLite

// MARK: - Test harness

@MainActor
private enum SubscriptionTestHarness {
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Expense.self,
            Subscription.self,
            Category.self,
            ExchangeRateCache.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func makeService(container: ModelContainer) -> SubscriptionService {
        SubscriptionService(
            context: container.mainContext,
            currencyService: CurrencyService(
                context: container.mainContext,
                primary: AlwaysOneRateFetcher(),
                fallback: AlwaysOneRateFetcher()
            )
        )
    }

    static func makeSub(
        name: String = "Netflix",
        amountMinor: Int = 1599,
        currencyCode: String = "USD",
        billingCycle: BillingCycle = .monthly,
        nextBillingDate: Date,
        status: SubscriptionStatus = .active,
        context: ModelContext
    ) throws -> Subscription {
        let sub = Subscription(
            name: name,
            amountMinor: amountMinor,
            currencyCode: currencyCode,
            billingCycle: billingCycle,
            nextBillingDate: nextBillingDate,
            status: status
        )
        context.insert(sub)
        try context.save()
        return sub
    }

    // Jan 1 2026 UTC midnight
    static let jan1: Date = Date(timeIntervalSince1970: 1_735_689_600)
}

// Rate fetcher that always returns 1:1 so we can test expense counts without network.
private struct AlwaysOneRateFetcher: RateFetching {
    func fetchRates(base: String, quotes: [String], on date: Date) async throws -> [String: Decimal] {
        Dictionary(uniqueKeysWithValues: quotes.map { ($0, Decimal(1)) })
    }
}

// Rate fetcher that suspends before answering, forcing an actor hop mid-generation —
// reproduces the window where a second generation pass can interleave.
private struct SlowOneRateFetcher: RateFetching {
    func fetchRates(base: String, quotes: [String], on date: Date) async throws -> [String: Decimal] {
        try await Task.sleep(for: .milliseconds(50))
        return Dictionary(uniqueKeysWithValues: quotes.map { ($0, Decimal(1)) })
    }
}

// MARK: - Cycle advancement

@Suite("SubscriptionService — cycle advancement", .serialized)
struct SubscriptionCycleAdvancementTests {

    @Test("Monthly — 3 missed months generates 3 expenses, advances billing date")
    @MainActor
    func monthlyThreeCycles() async throws {
        let container = try SubscriptionTestHarness.makeContainer()
        let service = SubscriptionTestHarness.makeService(container: container)
        let jan1 = SubscriptionTestHarness.jan1
        // nextBillingDate is 3 months ago → should generate 3 expenses
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: jan1)!
        let sub = try SubscriptionTestHarness.makeSub(
            billingCycle: .monthly,
            nextBillingDate: threeMonthsAgo,
            context: container.mainContext
        )

        try await service.generatePendingExpenses(referenceDate: jan1)

        let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 3)
        #expect(expenses.allSatisfy { $0.subscription?.id == sub.id })
        // After advancing 3 months, nextBillingDate should be >= jan1
        #expect(sub.nextBillingDate >= jan1)
    }

    @Test("customDays:14 — 56-day window generates 4 expenses")
    @MainActor
    func customDaysFourCycles() async throws {
        let container = try SubscriptionTestHarness.makeContainer()
        let service = SubscriptionTestHarness.makeService(container: container)
        let jan1 = SubscriptionTestHarness.jan1
        // 56 days before jan1 → 4 × 14-day cycles
        let start = Calendar.current.date(byAdding: .day, value: -56, to: jan1)!
        let sub = try SubscriptionTestHarness.makeSub(
            billingCycle: .customDays(14),
            nextBillingDate: start,
            context: container.mainContext
        )

        try await service.generatePendingExpenses(referenceDate: jan1)

        let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 4)
        #expect(sub.nextBillingDate >= jan1)
    }

    @Test("generatePendingExpenses is idempotent — calling twice does not double-generate")
    @MainActor
    func idempotent() async throws {
        let container = try SubscriptionTestHarness.makeContainer()
        let service = SubscriptionTestHarness.makeService(container: container)
        let jan1 = SubscriptionTestHarness.jan1
        let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: jan1)!
        _ = try SubscriptionTestHarness.makeSub(
            billingCycle: .monthly,
            nextBillingDate: oneMonthAgo,
            context: container.mainContext
        )

        try await service.generatePendingExpenses(referenceDate: jan1)
        try await service.generatePendingExpenses(referenceDate: jan1)

        let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 1)
    }

    @Test("Bills tab refresh does not destroy pending expense generation")
    @MainActor
    func billsTabRefreshKeepsMissedCycles() async throws {
        let container = try SubscriptionTestHarness.makeContainer()
        let service = SubscriptionTestHarness.makeService(container: container)
        // Two months overdue → two missed cycles that must become Expenses.
        let twoMonthsAgo = Calendar.current.date(byAdding: .month, value: -2, to: Date())!
        _ = try SubscriptionTestHarness.makeSub(
            billingCycle: .monthly,
            nextBillingDate: twoMonthsAgo,
            context: container.mainContext
        )

        // Simulate the user opening the Bills tab *before* launch generation ran.
        UserPreferences.homeCurrencyCode = "USD"   // match the USD sub → no network in either pass
        let vm = SubscriptionsViewModel(context: container.mainContext)
        vm.refresh()

        // Launch generation runs afterwards — it must still see the overdue dates.
        try await service.generatePendingExpenses()
        await vm.refreshTask?.value   // drain the tab's own pass before teardown

        let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 2, "missed billing cycles must be recorded as expenses, not silently skipped")
    }

    @Test("Concurrent generation passes do not double-generate")
    @MainActor
    func concurrentGenerationIsCoalesced() async throws {
        let container = try SubscriptionTestHarness.makeContainer()
        // EUR sub with USD home → the rate fetch suspends mid-loop (SlowOneRateFetcher).
        let service = SubscriptionService(
            context: container.mainContext,
            homeCurrencyCode: "USD",
            currencyService: CurrencyService(
                context: container.mainContext,
                primary: SlowOneRateFetcher(),
                fallback: SlowOneRateFetcher()
            )
        )
        let jan1 = SubscriptionTestHarness.jan1
        let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: jan1)!
        _ = try SubscriptionTestHarness.makeSub(
            currencyCode: "EUR",
            billingCycle: .monthly,
            nextBillingDate: oneMonthAgo,
            context: container.mainContext
        )

        // Launch-time pass and a Bills-tab pass running concurrently.
        async let first: Void = service.generatePendingExpenses(referenceDate: jan1)
        async let second: Void = service.generatePendingExpenses(referenceDate: jan1)
        _ = try await (first, second)

        let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 1, "the one missed cycle must produce exactly one expense")
    }

    @Test("Future nextBillingDate — no expenses generated")
    @MainActor
    func futureBillingDateSkipped() async throws {
        let container = try SubscriptionTestHarness.makeContainer()
        let service = SubscriptionTestHarness.makeService(container: container)
        let jan1 = SubscriptionTestHarness.jan1
        let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: jan1)!
        _ = try SubscriptionTestHarness.makeSub(
            billingCycle: .monthly,
            nextBillingDate: nextMonth,
            context: container.mainContext
        )

        try await service.generatePendingExpenses(referenceDate: jan1)

        let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(expenses.isEmpty)
    }
}

// MARK: - Paused / cancelled skip generation

@Suite("SubscriptionService — status gating", .serialized)
struct SubscriptionStatusGatingTests {

    @Test("Paused subscription does not generate expenses")
    @MainActor
    func pausedSkipsGeneration() async throws {
        let container = try SubscriptionTestHarness.makeContainer()
        let service = SubscriptionTestHarness.makeService(container: container)
        let jan1 = SubscriptionTestHarness.jan1
        let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: jan1)!
        _ = try SubscriptionTestHarness.makeSub(
            billingCycle: .monthly,
            nextBillingDate: oneMonthAgo,
            status: .paused,
            context: container.mainContext
        )

        try await service.generatePendingExpenses(referenceDate: jan1)

        let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(expenses.isEmpty)
    }

    @Test("Cancelled subscription does not generate expenses")
    @MainActor
    func cancelledSkipsGeneration() async throws {
        let container = try SubscriptionTestHarness.makeContainer()
        let service = SubscriptionTestHarness.makeService(container: container)
        let jan1 = SubscriptionTestHarness.jan1
        let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: jan1)!
        _ = try SubscriptionTestHarness.makeSub(
            billingCycle: .monthly,
            nextBillingDate: oneMonthAgo,
            status: .cancelled,
            context: container.mainContext
        )

        try await service.generatePendingExpenses(referenceDate: jan1)

        let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(expenses.isEmpty)
    }
}

// MARK: - Monthly equivalent sum

@Suite("Subscription — monthlyEquivalentMinorUnits", .serialized)
struct MonthlyEquivalentTests {

    @Test("Weekly subscription monthly equivalent = amount × 52/12")
    @MainActor
    func weeklyEquivalent() async throws {
        let container = try SubscriptionTestHarness.makeContainer()
        let sub = try SubscriptionTestHarness.makeSub(
            amountMinor: 1200,
            billingCycle: .weekly,
            nextBillingDate: SubscriptionTestHarness.jan1,
            context: container.mainContext
        )
        // 1200 × 52/12 = 5200 (rounded)
        let expected = Int(NSDecimalNumber(decimal: (Decimal(1200) * Decimal(52) / Decimal(12)).rounded(scale: 0)))
        #expect(sub.monthlyEquivalentMinorUnits() == expected)
    }

    @Test("Yearly subscription monthly equivalent = amount / 12")
    @MainActor
    func yearlyEquivalent() async throws {
        let container = try SubscriptionTestHarness.makeContainer()
        let sub = try SubscriptionTestHarness.makeSub(
            amountMinor: 12000,
            billingCycle: .yearly,
            nextBillingDate: SubscriptionTestHarness.jan1,
            context: container.mainContext
        )
        // 12000 / 12 = 1000
        #expect(sub.monthlyEquivalentMinorUnits() == 1000)
    }

    @Test("Monthly subscription monthly equivalent = amount")
    @MainActor
    func monthlyEquivalentIsIdentity() async throws {
        let container = try SubscriptionTestHarness.makeContainer()
        let sub = try SubscriptionTestHarness.makeSub(
            amountMinor: 999,
            billingCycle: .monthly,
            nextBillingDate: SubscriptionTestHarness.jan1,
            context: container.mainContext
        )
        #expect(sub.monthlyEquivalentMinorUnits() == 999)
    }

    @Test("customDays:30 monthly equivalent = amount × 30/30 = amount")
    @MainActor
    func customDays30EqualsMonthly() async throws {
        let container = try SubscriptionTestHarness.makeContainer()
        let sub = try SubscriptionTestHarness.makeSub(
            amountMinor: 500,
            billingCycle: .customDays(30),
            nextBillingDate: SubscriptionTestHarness.jan1,
            context: container.mainContext
        )
        #expect(sub.monthlyEquivalentMinorUnits() == 500)
    }
}

// MARK: - Notification identifier

@Suite("SubscriptionService — notification identifier")
struct NotificationIdentifierTests {

    @Test("Identifier is 'sub-' + UUID string")
    @MainActor
    func identifierFormat() {
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        let sub = Subscription(
            id: id,
            name: "Test",
            amountMinor: 100,
            currencyCode: "USD",
            billingCycle: .monthly,
            nextBillingDate: Date()
        )
        #expect(SubscriptionService.notificationIdentifier(for: sub) == "sub-12345678-1234-1234-1234-123456789ABC")
    }

    @Test("Identifier is stable across calls")
    @MainActor
    func identifierIsStable() {
        let sub = Subscription(
            name: "Spotify",
            amountMinor: 999,
            currencyCode: "USD",
            billingCycle: .monthly,
            nextBillingDate: Date()
        )
        let id1 = SubscriptionService.notificationIdentifier(for: sub)
        let id2 = SubscriptionService.notificationIdentifier(for: sub)
        #expect(id1 == id2)
    }
}

// MARK: - BillingCycle.nextDate

@Suite("BillingCycle — nextDate(after:)")
struct BillingCycleNextDateTests {

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    @Test("Monthly advances by one calendar month")
    func monthlyAdvance() {
        // Jan 31 + 1 month = Feb 28 (non-leap) or March 31 on some calendars
        let jan31 = SubscriptionTestHarness.jan1
        let next = BillingCycle.monthly.nextDate(after: jan31, calendar: utcCalendar)
        let comps = utcCalendar.dateComponents([.month], from: jan31, to: next)
        #expect(comps.month == 1)
    }

    @Test("Weekly advances by exactly 7 days")
    func weeklyAdvance() {
        let date = SubscriptionTestHarness.jan1
        let next = BillingCycle.weekly.nextDate(after: date, calendar: utcCalendar)
        let diff = utcCalendar.dateComponents([.day], from: date, to: next).day ?? 0
        #expect(diff == 7)
    }

    @Test("Yearly advances by one year")
    func yearlyAdvance() {
        let date = SubscriptionTestHarness.jan1
        let next = BillingCycle.yearly.nextDate(after: date, calendar: utcCalendar)
        let comps = utcCalendar.dateComponents([.year], from: date, to: next)
        #expect(comps.year == 1)
    }

    @Test("customDays(14) advances by exactly 14 days")
    func customDaysAdvance() {
        let date = SubscriptionTestHarness.jan1
        let next = BillingCycle.customDays(14).nextDate(after: date, calendar: utcCalendar)
        let diff = utcCalendar.dateComponents([.day], from: date, to: next).day ?? 0
        #expect(diff == 14)
    }
}

// MARK: - Decimal extension used in MonthlyEquivalent

private extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var result = Decimal()
        var mutableSelf = self
        NSDecimalRound(&result, &mutableSelf, scale, .plain)
        return result
    }
}
