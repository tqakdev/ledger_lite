import Testing
import Foundation
import SwiftData
@testable import LedgerLite

// MARK: - Harness

@MainActor
private enum ForecastHarness {
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Expense.self, Subscription.self, Category.self, ExchangeRateCache.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Configures the runway prefs the view model reads, returning a closure that restores them.
    static func setUpRunwayPrefs(balanceMinor: Int, payday: Date) -> () -> Void {
        let oldHome = UserPreferences.homeCurrencyCode
        let oldBalance = UserPreferences.availableBalanceMinor
        let oldAsOf = UserPreferences.balanceAsOfDate
        let oldPayday = UserPreferences.nextPayday
        UserPreferences.homeCurrencyCode = "USD"
        UserPreferences.availableBalanceMinor = balanceMinor
        UserPreferences.balanceAsOfDate = Date()
        UserPreferences.nextPayday = payday
        return {
            UserPreferences.homeCurrencyCode = oldHome
            UserPreferences.availableBalanceMinor = oldBalance
            UserPreferences.balanceAsOfDate = oldAsOf
            UserPreferences.nextPayday = oldPayday
        }
    }
}

// MARK: - Tests

@Suite("ForecastViewModel — foreign-currency bills", .serialized)
struct ForecastForeignBillTests {

    /// A future billing date can never have a cached rate (rates are cached for today and
    /// the past), so the runway must fall back to the freshest cached rate instead of
    /// silently using the foreign face value as home-currency minor units.
    @Test("future EUR bill converts using today's cached rate, not face value")
    @MainActor
    func futureBillUsesLatestCachedRate() async throws {
        let container = try ForecastHarness.makeContainer()
        let now = Date()
        let payday = Calendar.current.date(byAdding: .day, value: 14, to: now)!
        let restore = ForecastHarness.setUpRunwayPrefs(balanceMinor: 100_000, payday: payday)
        defer { restore() }

        // Today's EUR→USD rate is cached (the app fetches it on every form save).
        let rateRepo = ExchangeRateCacheRepository(context: container.mainContext)
        _ = try rateRepo.insertIfAbsent(
            base: "EUR",
            quote: "USD",
            rate: Decimal(string: "1.10", locale: Locale(identifier: "en_US_POSIX"))!,
            rateDate: Date.utcToday
        )

        // €10.00 monthly sub billing in 5 days — inside the runway window.
        let sub = Subscription(
            name: "Deutsche Cloud",
            amountMinor: 1000,
            currencyCode: "EUR",
            billingCycle: .monthly,
            nextBillingDate: Calendar.current.date(byAdding: .day, value: 5, to: now)!
        )
        container.mainContext.insert(sub)
        try container.mainContext.save()

        let vm = ForecastViewModel(context: container.mainContext)
        vm.refresh(now: now)

        let bills = try #require(vm.result?.upcomingBills)
        #expect(bills.count == 1)
        // €10.00 × 1.10 = $11.00 → 1100 minor units (not the €1000 face value).
        #expect(bills.first?.amountMinor == 1100)
    }

    @Test("no cached rate at all still falls back to face value")
    @MainActor
    func noRateFallsBackToFaceValue() async throws {
        let container = try ForecastHarness.makeContainer()
        let now = Date()
        let payday = Calendar.current.date(byAdding: .day, value: 14, to: now)!
        let restore = ForecastHarness.setUpRunwayPrefs(balanceMinor: 100_000, payday: payday)
        defer { restore() }

        let sub = Subscription(
            name: "Deutsche Cloud",
            amountMinor: 1000,
            currencyCode: "EUR",
            billingCycle: .monthly,
            nextBillingDate: Calendar.current.date(byAdding: .day, value: 5, to: now)!
        )
        container.mainContext.insert(sub)
        try container.mainContext.save()

        let vm = ForecastViewModel(context: container.mainContext)
        vm.refresh(now: now)

        #expect(vm.result?.upcomingBills.first?.amountMinor == 1000)
    }
}
