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
        Money(minorUnits: todayTotalMinor, currencyCode: homeCurrencyCode).formatted()
    }

    func refresh() {
        homeCurrencyCode = UserPreferences.homeCurrencyCode
        do {
            expenses = try expenseRepository.fetchToday()
            todayTotalMinor = totalInHomeCurrency(expenses)
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

    /// Sums expenses in home-currency minor units.
    /// Accumulates raw Decimal before rounding once at the end — avoids per-row rounding drift.
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
