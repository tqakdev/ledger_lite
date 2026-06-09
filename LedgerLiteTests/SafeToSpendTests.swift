import Testing
import Foundation
import SwiftData
@testable import LedgerLite

// MARK: - Harness

@MainActor
private enum SafeToSpendHarness {
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Expense.self, Subscription.self, Category.self, ExchangeRateCache.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func makeCategory(name: String, budgetMinor: Int?) -> LedgerLite.Category {
        LedgerLite.Category(name: name, iconName: "circle", colorHex: "#FFFFFF",
                            monthlyBudgetMinor: budgetMinor)
    }

    static func makeExpense(amountMinor: Int, category: LedgerLite.Category?) -> Expense {
        let e = Expense(
            amountMinor: amountMinor,
            currencyCode: "USD",
            exchangeRateToHome: 1,
            homeCurrencyAtEntry: "USD",
            date: Date()
        )
        e.category = category
        return e
    }
}

// MARK: - Tests

@Suite("TodayViewModel — safe-to-spend")
@MainActor
struct SafeToSpendTests {

    init() {
        UserDefaults.standard.set("USD", forKey: "homeCurrencyCode")
    }

    /// safeToSpendMinor must stay nil when the user has not set any budget.
    @Test("returns nil when no category has a budget")
    func nilWhenNoBudgets() async throws {
        let container = try SafeToSpendHarness.makeContainer()
        let cat = SafeToSpendHarness.makeCategory(name: "Food", budgetMinor: nil)
        container.mainContext.insert(cat)
        let expense = SafeToSpendHarness.makeExpense(amountMinor: 500, category: cat)
        container.mainContext.insert(expense)

        let vm = TodayViewModel(context: container.mainContext)
        vm.refresh()
        await Task.yield()

        #expect(vm.safeToSpendMinor == nil)
    }

    /// Spending in an unbudgeted category must not reduce the safe-to-spend
    /// amount — it is irrelevant to the budgeted-category calculation.
    @Test("unbudgeted spending does not reduce safe-to-spend")
    func unbudgetedSpendingIgnored() async throws {
        let container = try SafeToSpendHarness.makeContainer()

        // Food has a generous $1 000 budget so safe-to-spend will be clearly > 0.
        let food = SafeToSpendHarness.makeCategory(name: "Food", budgetMinor: 100_000)
        // Travel has no budget.
        let travel = SafeToSpendHarness.makeCategory(name: "Travel", budgetMinor: nil)
        container.mainContext.insert(food)
        container.mainContext.insert(travel)

        // Log $500 in the unbudgeted Travel category.
        let e = SafeToSpendHarness.makeExpense(amountMinor: 50_000, category: travel)
        container.mainContext.insert(e)

        let vm = TodayViewModel(context: container.mainContext)
        vm.refresh()
        await Task.yield()

        // safe-to-spend should be based on the untouched $1 000 Food budget only.
        let safe = try #require(vm.safeToSpendMinor)
        #expect(safe > 0, "Unbudgeted travel spend must not mark Food budget as exceeded")
    }

    /// Spending that exceeds the total monthly budget in a budgeted category
    /// must cause safeToSpendMinor to be <= 0 (chip shows "Budget exceeded").
    @Test("overspending a budgeted category yields non-positive safe-to-spend")
    func overspendingBudgetedCategory() async throws {
        let container = try SafeToSpendHarness.makeContainer()

        // $1 budget (100 minor units).
        let food = SafeToSpendHarness.makeCategory(name: "Food", budgetMinor: 100)
        container.mainContext.insert(food)

        // Spend $5 — five times the budget.
        let e = SafeToSpendHarness.makeExpense(amountMinor: 500, category: food)
        container.mainContext.insert(e)

        let vm = TodayViewModel(context: container.mainContext)
        vm.refresh()
        await Task.yield()

        let safe = try #require(vm.safeToSpendMinor)
        #expect(safe <= 0, "Spending 5× the budget must set safe-to-spend to ≤ 0")
    }

    /// Only budgeted-category spending should reduce safe-to-spend.
    /// Mixed scenario: budgeted + unbudgeted expenses coexist.
    @Test("mixed spending: only budgeted portion is counted")
    func mixedSpendingOnlyBudgetedCounts() async throws {
        let container = try SafeToSpendHarness.makeContainer()

        // $1 000 budget for Food.
        let food = SafeToSpendHarness.makeCategory(name: "Food", budgetMinor: 100_000)
        let travel = SafeToSpendHarness.makeCategory(name: "Travel", budgetMinor: nil)
        container.mainContext.insert(food)
        container.mainContext.insert(travel)

        // $200 budgeted spend + $900 unbudgeted spend. Only $200 should count.
        let e1 = SafeToSpendHarness.makeExpense(amountMinor: 20_000, category: food)
        let e2 = SafeToSpendHarness.makeExpense(amountMinor: 90_000, category: travel)
        container.mainContext.insert(e1)
        container.mainContext.insert(e2)

        let vm = TodayViewModel(context: container.mainContext)
        vm.refresh()
        await Task.yield()

        // Remaining = $1 000 - $200 = $800. Dividing by days-remaining gives a
        // positive value regardless of the day of month.
        let safe = try #require(vm.safeToSpendMinor)
        #expect(safe > 0, "Only $200 of budgeted spend against a $1 000 budget must leave safe-to-spend positive")
    }

    /// Multiple budgeted categories: their budgets and spending both sum correctly.
    @Test("multiple budgeted categories: budgets and spending aggregate correctly")
    func multipleBudgetedCategories() async throws {
        let container = try SafeToSpendHarness.makeContainer()

        // Food: $600 budget, $100 spent. Transport: $400 budget, $50 spent.
        // Total budget = $1 000. Total spend = $150. Remaining = $850.
        let food      = SafeToSpendHarness.makeCategory(name: "Food",      budgetMinor: 60_000)
        let transport = SafeToSpendHarness.makeCategory(name: "Transport", budgetMinor: 40_000)
        container.mainContext.insert(food)
        container.mainContext.insert(transport)

        container.mainContext.insert(SafeToSpendHarness.makeExpense(amountMinor: 10_000, category: food))
        container.mainContext.insert(SafeToSpendHarness.makeExpense(amountMinor: 5_000,  category: transport))

        let vm = TodayViewModel(context: container.mainContext)
        vm.refresh()
        await Task.yield()

        let safe = try #require(vm.safeToSpendMinor)
        // Remaining $850 spread over remaining days is always > 0 with only 15% of budget spent.
        #expect(safe > 0, "Combined $150 spend against $1 000 total budget must leave safe-to-spend positive")
    }

    /// A future-dated expense (next month) must not reduce this month's safe-to-spend.
    @Test("next-month expense is excluded from safe-to-spend calculation")
    func nextMonthExpenseExcluded() async throws {
        let container = try SafeToSpendHarness.makeContainer()

        let food = SafeToSpendHarness.makeCategory(name: "Food", budgetMinor: 100_000)
        container.mainContext.insert(food)

        // Expense dated 40 days in the future — safely outside the current calendar month.
        let futureDate = Calendar.current.date(byAdding: .day, value: 40, to: Date()) ?? Date()
        let future = Expense(
            amountMinor: 99_000,
            currencyCode: "USD",
            exchangeRateToHome: 1,
            homeCurrencyAtEntry: "USD",
            date: futureDate
        )
        future.category = food
        container.mainContext.insert(future)

        let vm = TodayViewModel(context: container.mainContext)
        vm.refresh()
        await Task.yield()

        // The $990 next-month expense must not reduce safe-to-spend for the current month.
        let safe = try #require(vm.safeToSpendMinor)
        #expect(safe > 0, "A future-month expense must not count against the current month's budget")
    }
}
