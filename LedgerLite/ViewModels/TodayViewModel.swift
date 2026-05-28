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
    var dailyAverageMinor: Int = 0
    var homeCurrencyCode: String = UserPreferences.homeCurrencyCode
    var activeSheet: TodaySheet?
    var errorMessage: String?
    var isLoading: Bool = false
    var currentStreak: Int = 0

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
            todayTotalMinor = expenses.totalInHomeCurrency(homeCurrencyCode)
            dailyAverageMinor = computeDailyAverage()
            currentStreak = computeStreak()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.ui.error("Today refresh failed: \(error)")
        }
        isLoading = false
        Task { BudgetAlertService(context: modelContext).checkBudgets() }
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

    func presentQuickAdd() { activeSheet = .quickAdd }
    func presentEdit(for expense: Expense) { activeSheet = .edit(expense) }

    func dismissSheet() {
        activeSheet = nil
        refresh()
    }

    // MARK: - Private

    private func computeStreak() -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Cap the look-back at 366 days — no realistic streak exceeds a year
        guard let cutoff = cal.date(byAdding: .day, value: -366, to: today) else { return 0 }
        let since = cutoff
        let fetched = (try? modelContext.fetch(
            FetchDescriptor<Expense>(
                predicate: #Predicate { $0.date >= since },
                sortBy: []
            )
        )) ?? []
        let expenseDays = Set(fetched.map { cal.startOfDay(for: $0.date) })
        var streak = 0
        var checkDate = today
        while expenseDays.contains(checkDate) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }
        return streak
    }

    private func computeDailyAverage() -> Int {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else { return 0 }
        do {
            let since = thirtyDaysAgo
            let recent = try modelContext.fetch(
                FetchDescriptor<Expense>(
                    predicate: #Predicate { $0.date >= since },
                    sortBy: []
                )
            )
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
