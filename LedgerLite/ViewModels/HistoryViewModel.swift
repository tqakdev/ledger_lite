import Foundation
import SwiftData
import WidgetKit

enum HistorySheet: Identifiable {
    case add
    case scanReceipt
    case edit(Expense)

    var id: String {
        switch self {
        case .add:               return "add"
        case .scanReceipt:       return "scan"
        case .edit(let expense): return "edit-\(expense.id.uuidString)"
        }
    }

    var formMode: ExpenseFormMode {
        switch self {
        case .add, .scanReceipt: return .add
        case .edit(let expense): return .edit(expense)
        }
    }

    /// True when the form should open straight into the receipt scanner.
    var startsWithScan: Bool {
        if case .scanReceipt = self { return true }
        return false
    }
}

@MainActor
@Observable
final class HistoryViewModel {
    var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    var expenses: [Expense] = []
    var dayTotalMinor: Int = 0
    var monthTotalMinor: Int = 0
    var homeCurrencyCode: String = UserPreferences.homeCurrencyCode
    var activeSheet: HistorySheet?
    var errorMessage: String?
    var isLoading: Bool = false
    var searchText: String = ""
    var categories: [Category] = []
    var selectedCategoryFilter: Category? = nil
    var searchResults: [Expense] = []

    private let expenseRepository: ExpenseRepository
    private let modelContext: ModelContext
    private var searchTask: Task<Void, Never>?

    init(context: ModelContext) {
        self.modelContext = context
        self.expenseRepository = ExpenseRepository(context: context)
    }

    var isGlobalSearch: Bool { !searchText.isEmpty }

    // Categories that actually appear in today's expenses — cached here so the view
    // doesn't recompute O(categories × expenses) on every render.
    var presentCategories: [Category] {
        let ids = Set(expenses.compactMap { $0.category?.id })
        return categories.filter { ids.contains($0.id) }
    }

    var filteredExpenses: [Expense] {
        var result = expenses
        if let cat = selectedCategoryFilter {
            let catId = cat.id
            result = result.filter { $0.category?.id == catId }
        }
        if !searchText.isEmpty {
            result = result.filter { matches($0, query: searchText) }
        }
        return result
    }

    var dayTotalFormatted: String {
        Money(minorUnits: dayTotalMinor, currencyCode: homeCurrencyCode).formatted()
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    // MARK: - Search

    func scheduleSearch() {
        searchTask?.cancel()
        guard !searchText.isEmpty else { searchResults = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            runGlobalSearchNow()
        }
    }

    /// Search results are capped — nobody scrolls hundreds of matches, and the
    /// cap keeps multi-year stores from being loaded into memory.
    private static let searchResultLimit = 200

    /// Executes the global search immediately (the debounce lives in
    /// `scheduleSearch`). Internal so tests can drive it synchronously.
    ///
    /// The match runs in the store via `#Predicate` (`localizedStandardContains`
    /// is case- and diacritic-insensitive) instead of fetching every expense and
    /// filtering in memory.
    func runGlobalSearchNow() {
        guard !searchText.isEmpty else { searchResults = []; return }
        let q = searchText
        var descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate {
                ($0.merchant?.localizedStandardContains(q) ?? false) ||
                ($0.note?.localizedStandardContains(q) ?? false) ||
                ($0.category?.name.localizedStandardContains(q) ?? false)
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = Self.searchResultLimit
        var results = (try? modelContext.fetch(descriptor)) ?? []
        if let cat = selectedCategoryFilter {
            let catId = cat.id
            results = results.filter { $0.category?.id == catId }
        }
        searchResults = results
    }

    // MARK: - Navigation

    func previousDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        refresh()
    }

    func nextDay() {
        guard !isToday else { return }
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        refresh()
    }

    func refresh() {
        isLoading = true
        homeCurrencyCode = UserPreferences.homeCurrencyCode
        categories = (try? modelContext.fetch(
            FetchDescriptor<Category>(sortBy: [SortDescriptor(\.name)])
        )) ?? []
        do {
            let cal = Calendar.current
            let dayStart = cal.startOfDay(for: selectedDate)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? Date.distantFuture
            expenses = try modelContext.fetch(
                FetchDescriptor<Expense>(
                    predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd },
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                )
            )
            dayTotalMinor = expenses.totalInHomeCurrency(homeCurrencyCode)
            monthTotalMinor = computeMonthTotal()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.ui.error("History refresh failed: \(error)")
        }
        isLoading = false
        // An active global search must reflect edits and deletes immediately —
        // otherwise removed rows linger in the results list.
        if isGlobalSearch { runGlobalSearchNow() }
    }

    func deleteExpense(_ expense: Expense) {
        let id = expense.id
        do {
            try expenseRepository.delete(expense)
            SpotlightService.deindex(id)
            // Deleting changed the data the home-screen widgets read — refresh now
            // instead of waiting for the next ~30-minute system reload.
            WidgetCenter.shared.reloadAllTimelines()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func presentAdd() { activeSheet = .add }
    func presentScan() { activeSheet = .scanReceipt }
    func presentEdit(for expense: Expense) { activeSheet = .edit(expense) }

    func dismissSheet() {
        activeSheet = nil
        refresh()
    }

    // MARK: - Private

    // Same case- and diacritic-insensitive match as the global search predicate,
    // so the day filter and global results never disagree on what "matches".
    private func matches(_ expense: Expense, query: String) -> Bool {
        (expense.merchant?.localizedStandardContains(query) ?? false) ||
        (expense.note?.localizedStandardContains(query) ?? false) ||
        (expense.category?.name.localizedStandardContains(query) ?? false)
    }

    private func computeMonthTotal() -> Int {
        let cal = Calendar.current
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: selectedDate)),
              let nextMonth = cal.date(byAdding: .month, value: 1, to: monthStart) else { return 0 }
        let monthExpenses = (try? modelContext.fetch(
            FetchDescriptor<Expense>(
                predicate: #Predicate { $0.date >= monthStart && $0.date < nextMonth },
                sortBy: []
            )
        )) ?? []
        return monthExpenses.totalInHomeCurrency(homeCurrencyCode)
    }
}
