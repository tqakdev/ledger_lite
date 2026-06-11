import Testing
import Foundation
import SwiftData
@testable import LedgerLite

@MainActor
@Suite("HistoryViewModel — global search")
struct HistorySearchTests {

    /// Returns a seeded container. The caller must keep it alive — the context
    /// borrows from it, and a deallocated container takes the store down with it.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Expense.self, Subscription.self, LedgerLite.Category.self, ExchangeRateCache.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @discardableResult
    private func seed(
        _ context: ModelContext,
        merchant: String? = nil,
        note: String? = nil,
        category: LedgerLite.Category? = nil,
        daysAgo: Int = 0
    ) -> Expense {
        let expense = Expense(
            amountMinor: 1000,
            currencyCode: "USD",
            homeCurrencyAtEntry: "USD",
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
            note: note,
            merchant: merchant
        )
        expense.category = category
        context.insert(expense)
        return expense
    }

    @Test("matches merchant case- and diacritic-insensitively")
    func diacriticInsensitiveMerchant() throws {
        let container = try makeContainer()
        let context = container.mainContext
        seed(context, merchant: "Café Luna")
        seed(context, merchant: "Hardware Depot")
        try context.save()

        let vm = HistoryViewModel(context: context)
        vm.searchText = "cafe"
        vm.runGlobalSearchNow()

        #expect(vm.searchResults.count == 1)
        #expect(vm.searchResults.first?.merchant == "Café Luna")
    }

    @Test("matches note and category name")
    func noteAndCategoryMatch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let groceries = LedgerLite.Category(name: "Groceries", iconName: "cart.fill", colorHex: "#45B7D1")
        context.insert(groceries)
        seed(context, merchant: "Shop A", note: "birthday gift")
        seed(context, merchant: "Shop B", category: groceries)
        try context.save()

        let vm = HistoryViewModel(context: context)
        vm.searchText = "birthday"
        vm.runGlobalSearchNow()
        #expect(vm.searchResults.count == 1)
        #expect(vm.searchResults.first?.merchant == "Shop A")

        vm.searchText = "grocer"
        vm.runGlobalSearchNow()
        #expect(vm.searchResults.count == 1)
        #expect(vm.searchResults.first?.merchant == "Shop B")
    }

    @Test("category filter applies to global search results")
    func categoryFilterApplies() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let food = LedgerLite.Category(name: "Food", iconName: "fork.knife", colorHex: "#FF6B35")
        let travel = LedgerLite.Category(name: "Travel", iconName: "airplane", colorHex: "#F7DC6F")
        context.insert(food)
        context.insert(travel)
        seed(context, merchant: "Star Cafe", category: food)
        seed(context, merchant: "Star Hotel", category: travel)
        try context.save()

        let vm = HistoryViewModel(context: context)
        vm.searchText = "star"
        vm.selectedCategoryFilter = food
        vm.runGlobalSearchNow()

        #expect(vm.searchResults.count == 1)
        #expect(vm.searchResults.first?.merchant == "Star Cafe")
    }

    @Test("results are sorted newest first")
    func sortedNewestFirst() throws {
        let container = try makeContainer()
        let context = container.mainContext
        seed(context, merchant: "Star Cafe old", daysAgo: 10)
        seed(context, merchant: "Star Cafe new", daysAgo: 1)
        try context.save()

        let vm = HistoryViewModel(context: context)
        vm.searchText = "star"
        vm.runGlobalSearchNow()

        #expect(vm.searchResults.map(\.merchant) == ["Star Cafe new", "Star Cafe old"])
    }

    @Test("deleting an expense refreshes active search results (no stale rows)")
    func deleteRefreshesSearch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = seed(context, merchant: "Star Cafe", daysAgo: 1)
        seed(context, merchant: "Star Bistro", daysAgo: 2)
        try context.save()

        let vm = HistoryViewModel(context: context)
        vm.searchText = "star"
        vm.runGlobalSearchNow()
        #expect(vm.searchResults.count == 2)

        vm.deleteExpense(first)

        #expect(vm.searchResults.count == 1)
        #expect(vm.searchResults.first?.merchant == "Star Bistro")
    }
}
