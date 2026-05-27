import Foundation
import SwiftData

enum HistorySheet: Identifiable {
    case edit(Expense)

    var id: String {
        switch self {
        case .edit(let expense): return "edit-\(expense.id.uuidString)"
        }
    }

    var formMode: ExpenseFormMode {
        switch self {
        case .edit(let expense): return .edit(expense)
        }
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

    private let expenseRepository: ExpenseRepository
    private let modelContext: ModelContext

    init(context: ModelContext) {
        self.modelContext = context
        self.expenseRepository = ExpenseRepository(context: context)
    }

    var isGlobalSearch: Bool { !searchText.isEmpty }

    var filteredExpenses: [Expense] {
        var result = expenses
        if let cat = selectedCategoryFilter {
            let catId = cat.id
            result = result.filter { $0.category?.id == catId }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                ($0.merchant?.lowercased().contains(q) ?? false) ||
                ($0.note?.lowercased().contains(q) ?? false) ||
                ($0.category?.name.lowercased().contains(q) ?? false)
            }
        }
        return result
    }

    var searchResults: [Expense] = []

    func performGlobalSearch() {
        guard !searchText.isEmpty else { searchResults = []; return }
        let q = searchText.lowercased()
        guard let all = try? modelContext.fetch(
            FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        ) else { return }
        var results = all.filter {
            ($0.merchant?.lowercased().contains(q) ?? false) ||
            ($0.note?.lowercased().contains(q) ?? false) ||
            ($0.category?.name.lowercased().contains(q) ?? false)
        }
        if let cat = selectedCategoryFilter {
            let catId = cat.id
            results = results.filter { $0.category?.id == catId }
        }
        searchResults = results
    }

    var dayTotalFormatted: String {
        Money(minorUnits: dayTotalMinor, currencyCode: homeCurrencyCode).formatted()
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

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
    }

    func deleteExpense(_ expense: Expense) {
        let id = expense.id
        do {
            try expenseRepository.delete(expense)
            SpotlightService.deindex(id)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func presentEdit(for expense: Expense) {
        activeSheet = .edit(expense)
    }

    func dismissSheet() {
        activeSheet = nil
        refresh()
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
