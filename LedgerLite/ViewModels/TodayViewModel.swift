import Foundation
import SwiftData

enum TodaySheet: Identifiable {
    case quickAdd
    case edit(Expense)

    var id: String {
        switch self {
        case .quickAdd: return "quickAdd"
        case .edit(let expense): return "edit-\(expense.id.uuidString)"
        }
    }

    var formMode: ExpenseFormMode {
        switch self {
        case .quickAdd: return .add
        case .edit(let expense): return .edit(expense)
        }
    }
}

@MainActor
@Observable
final class TodayViewModel {
    var expenses: [Expense] = []
    var todayTotalMinor: Int = 0
    var homeCurrencyCode: String = UserPreferences.homeCurrencyCode
    var activeSheet: TodaySheet?
    var errorMessage: String?

    private let expenseRepository: ExpenseRepository
    private let modelContext: ModelContext

    init(context: ModelContext) {
        self.modelContext = context
        self.expenseRepository = ExpenseRepository(context: context)
    }

    var todayTotalFormatted: String {
        Money(minorUnits: todayTotalMinor, currencyCode: homeCurrencyCode)
            .formatted(locale: Locale(identifier: "en_US"))
    }

    func refresh() {
        homeCurrencyCode = UserPreferences.homeCurrencyCode
        do {
            expenses = try expenseRepository.fetchToday()
            todayTotalMinor = expenses.reduce(0) { partial, expense in
                partial + homeAmountMinor(for: expense)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.ui.error("Today refresh failed: \(error)")
        }
    }

    func deleteExpense(_ expense: Expense) {
        do {
            try expenseRepository.delete(expense)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func presentQuickAdd() {
        activeSheet = .quickAdd
    }

    func presentEdit(for expense: Expense) {
        activeSheet = .edit(expense)
    }

    func dismissSheet() {
        activeSheet = nil
        refresh()
    }

    // MARK: - Private

    private func homeAmountMinor(for expense: Expense) -> Int {
        if expense.currencyCode == expense.homeCurrencyAtEntry {
            return expense.amountMinor
        }
        return Money(minorUnits: expense.amountMinor, currencyCode: expense.currencyCode)
            .converted(to: expense.homeCurrencyAtEntry, rate: expense.exchangeRateToHome)
            .minorUnits
    }
}
