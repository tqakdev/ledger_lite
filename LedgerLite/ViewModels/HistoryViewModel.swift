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
            dayTotalMinor = totalInHomeCurrency(expenses)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.ui.error("History refresh failed: \(error)")
        }
        isLoading = false
    }

    func deleteExpense(_ expense: Expense) {
        do {
            try expenseRepository.delete(expense)
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

    private func totalInHomeCurrency(_ expenses: [Expense]) -> Int {
        let homePlaces = Money.decimals(for: homeCurrencyCode)
        var accumulated = Decimal(0)
        for expense in expenses {
            if expense.currencyCode == expense.homeCurrencyAtEntry {
                accumulated += Decimal(expense.amountMinor)
            } else {
                let srcDecimal = expense.money.decimalValue
                let homeMinorDecimal = srcDecimal * expense.exchangeRateToHome * Decimal.powerOfTen(homePlaces)
                accumulated += homeMinorDecimal
            }
        }
        let rounded = accumulated.rounded(scale: 0)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
