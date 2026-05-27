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
    var dailyAverageMinor: Int = 0     // A5: 30-day daily average in home-currency minor units
    var homeCurrencyCode: String = UserPreferences.homeCurrencyCode
    var activeSheet: TodaySheet?
    var errorMessage: String?
    var isLoading: Bool = false         // C4

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
        isLoading = true
        homeCurrencyCode = UserPreferences.homeCurrencyCode
        do {
            expenses = try expenseRepository.fetchToday()
            todayTotalMinor = totalInHomeCurrency(expenses)
            dailyAverageMinor = computeDailyAverage()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.ui.error("Today refresh failed: \(error)")
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

    // A5: fetch last 30 days of expenses and return the sum ÷ 30 in home-currency minor units.
    private func computeDailyAverage() -> Int {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else { return 0 }
        do {
            let all = try expenseRepository.fetchAll()
            let recent = all.filter { $0.date >= thirtyDaysAgo }
            guard !recent.isEmpty else { return 0 }
            let homePlaces = Money.decimals(for: homeCurrencyCode)
            var sum = Decimal(0)
            for e in recent {
                if e.currencyCode == e.homeCurrencyAtEntry {
                    sum += Decimal(e.amountMinor)
                } else {
                    sum += e.money.decimalValue * e.exchangeRateToHome * Decimal.powerOfTen(homePlaces)
                }
            }
            let rounded = sum.rounded(scale: 0)
            let totalMinor = NSDecimalNumber(decimal: rounded).intValue
            return totalMinor / 30
        } catch {
            AppLogger.ui.error("Daily average failed: \(error)")
            return 0
        }
    }
}
