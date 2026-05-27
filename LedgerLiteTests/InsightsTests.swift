import Testing
import Foundation
import SwiftData
@testable import LedgerLite

// MARK: - Test harness

@MainActor
private enum InsightsTestHarness {
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Expense.self, Subscription.self, Category.self, ExchangeRateCache.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func makeExpense(amountMinor: Int, currencyCode: String = "USD",
                            rate: Decimal = 1, date: Date) -> Expense {
        Expense(
            amountMinor: amountMinor,
            currencyCode: currencyCode,
            exchangeRateToHome: rate,
            homeCurrencyAtEntry: "USD",
            date: date
        )
    }

    /// 2026-05-27 00:00:00 UTC — fixed reference date for all filtering tests.
    static let ref = Date(timeIntervalSince1970: 1_748_304_000)
}

// MARK: - Period filtering

@Suite("InsightsViewModel — period filtering")
@MainActor
struct PeriodFilteringTests {

    // Set home currency to USD before each test so decimal places are always 2.
    init() {
        UserDefaults.standard.set("USD", forKey: "homeCurrencyCode")
    }

    @Test("week period: expense within current week is counted, older expense is excluded")
    func weekPeriod() async throws {
        let container = try InsightsTestHarness.makeContainer()
        let ref       = InsightsTestHarness.ref

        // 10 days before ref is always outside any 7-day calendar week
        container.mainContext.insert(InsightsTestHarness.makeExpense(amountMinor: 1000, date: ref))
        container.mainContext.insert(InsightsTestHarness.makeExpense(amountMinor: 2000, date: ref.adding(days: -10)))

        let vm = InsightsViewModel(context: container.mainContext)
        vm.period = .week
        await vm.refresh(referenceDate: ref)

        #expect(vm.periodTotalMinor == 1000)
    }

    @Test("month period: expense this month is counted, expense last month is excluded")
    func monthPeriod() async throws {
        let container = try InsightsTestHarness.makeContainer()
        let ref       = InsightsTestHarness.ref

        // -32 days from May 27 lands in April regardless of timezone
        container.mainContext.insert(InsightsTestHarness.makeExpense(amountMinor: 1500, date: ref))
        container.mainContext.insert(InsightsTestHarness.makeExpense(amountMinor: 3000, date: ref.adding(days: -32)))

        let vm = InsightsViewModel(context: container.mainContext)
        vm.period = .month
        await vm.refresh(referenceDate: ref)

        #expect(vm.periodTotalMinor == 1500)
    }

    @Test("year period: expense this year is counted, expense last year is excluded")
    func yearPeriod() async throws {
        let container = try InsightsTestHarness.makeContainer()
        let ref       = InsightsTestHarness.ref

        // -366 days always lands in 2025
        container.mainContext.insert(InsightsTestHarness.makeExpense(amountMinor: 4000, date: ref))
        container.mainContext.insert(InsightsTestHarness.makeExpense(amountMinor: 8000, date: ref.adding(days: -366)))

        let vm = InsightsViewModel(context: container.mainContext)
        vm.period = .year
        await vm.refresh(referenceDate: ref)

        #expect(vm.periodTotalMinor == 4000)
    }

    @Test("allTime period: all expenses are counted regardless of age")
    func allTimePeriod() async throws {
        let container = try InsightsTestHarness.makeContainer()
        let ref       = InsightsTestHarness.ref

        container.mainContext.insert(InsightsTestHarness.makeExpense(amountMinor: 2000, date: ref))
        container.mainContext.insert(InsightsTestHarness.makeExpense(amountMinor: 3000, date: ref.adding(days: -700)))

        let vm = InsightsViewModel(context: container.mainContext)
        vm.period = .allTime
        await vm.refresh(referenceDate: ref)

        #expect(vm.periodTotalMinor == 5000)
    }
}

// MARK: - Currency conversion

@Suite("InsightsViewModel — currency conversion")
@MainActor
struct CurrencyConversionTests {

    init() {
        UserDefaults.standard.set("USD", forKey: "homeCurrencyCode")
    }

    @Test("same-currency expense: minor units are preserved exactly")
    func sameCurrencyPreservesMinorUnits() async throws {
        let container = try InsightsTestHarness.makeContainer()
        // USD 50.00 with identity rate — expects 5000 minor units back
        container.mainContext.insert(
            InsightsTestHarness.makeExpense(amountMinor: 5000, currencyCode: "USD", rate: 1, date: Date())
        )

        let vm = InsightsViewModel(context: container.mainContext)
        vm.period = .allTime
        await vm.refresh()

        #expect(vm.periodTotalMinor == 5000)
    }

    @Test("foreign-currency expense: amount is multiplied by frozen exchangeRateToHome")
    func foreignCurrencyUseFrozenRate() async throws {
        let container = try InsightsTestHarness.makeContainer()
        // EUR 10.00 (1000 minor units) at frozen rate 2.0 → USD 20.00 = 2000 minor units
        container.mainContext.insert(
            InsightsTestHarness.makeExpense(
                amountMinor: 1000,
                currencyCode: "EUR",
                rate: Decimal(safeString: "2.00"),
                date: Date()
            )
        )

        let vm = InsightsViewModel(context: container.mainContext)
        vm.period = .allTime
        await vm.refresh()

        #expect(vm.periodTotalMinor == 2000)
    }
}
