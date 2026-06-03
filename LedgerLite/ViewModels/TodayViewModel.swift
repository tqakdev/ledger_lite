import Foundation
import SwiftData

enum TodaySheet: Identifiable {
    case quickAdd
    case scanReceipt
    case edit(Expense)

    var id: String {
        switch self {
        case .quickAdd: return "quickAdd"
        case .scanReceipt: return "scanReceipt"
        case .edit(let expense): return "edit-\(expense.id.uuidString)"
        }
    }

    var formMode: ExpenseFormMode {
        switch self {
        case .quickAdd, .scanReceipt: return .add
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
final class TodayViewModel {
    var expenses: [Expense] = []
    var todayTotalMinor: Int = 0
    var dailyAverageMinor: Int = 0
    var homeCurrencyCode: String = UserPreferences.homeCurrencyCode
    var activeSheet: TodaySheet?
    var errorMessage: String?
    var isLoading: Bool = false
    var currentStreak: Int = 0
    /// Remaining monthly budget divided by days left in the month.
    /// nil when no category budgets have been set.
    var safeToSpendMinor: Int? = nil

    private let expenseRepository: ExpenseRepository
    private let modelContext: ModelContext
    private var metricsTask: Task<Void, Never>?

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
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.ui.error("Today refresh failed: \(error)")
        }
        isLoading = false
        // Defer expensive historical queries so the main list renders first.
        // Coalesce rapid refreshes (appear/dismiss/delete) by cancelling any
        // in-flight pass, so a stale computation can't overwrite fresher values
        // or trigger a duplicate budget check.
        metricsTask?.cancel()
        metricsTask = Task {
            let average = computeDailyAverage()
            let streak  = computeStreak()
            let safe    = computeSafeToSpend()
            guard !Task.isCancelled else { return }
            dailyAverageMinor = average
            currentStreak = streak
            safeToSpendMinor = safe
            BudgetAlertService(context: modelContext).checkBudgets()
        }
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
    func presentScan() { activeSheet = .scanReceipt }
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
        let now = Date()
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) else { return 0 }
        do {
            let since = thirtyDaysAgo
            let upperBound = now
            let recent = try modelContext.fetch(
                FetchDescriptor<Expense>(
                    predicate: #Predicate { $0.date >= since && $0.date <= upperBound },
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

    // Returns (total monthly budget - month-to-date spending in budgeted categories) / days remaining.
    // Returns nil when no category has a budget set, so the chip is hidden by default.
    // Only spending in categories that carry a budget is counted — unbudgeted categories
    // (e.g. a one-off "Travel" spend) must not reduce safe-to-spend for budgeted categories.
    private func computeSafeToSpend() -> Int? {
        let cal = Calendar.current
        let now = Date()

        let categories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        let totalBudget = categories.compactMap(\.monthlyBudgetMinor).reduce(0, +)
        guard totalBudget > 0 else { return nil }

        var monthComps = cal.dateComponents([.year, .month], from: now)
        monthComps.day = 1
        guard let monthStart = cal.date(from: monthComps),
              let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { return nil }

        let monthExpenses = (try? modelContext.fetch(
            FetchDescriptor<Expense>(
                predicate: #Predicate { $0.date >= monthStart && $0.date < monthEnd },
                sortBy: []
            )
        )) ?? []

        // Filter to only expenses whose category has a monthly budget set.
        // Unbudgeted spending should not penalise the safe-to-spend calculation.
        let budgetedExpenses = monthExpenses.filter { ($0.category?.monthlyBudgetMinor ?? 0) > 0 }
        let totalSpent = budgetedExpenses.totalInHomeCurrency(homeCurrencyCode)

        guard let monthRange = cal.range(of: .day, in: .month, for: now),
              let dayOfMonth = cal.dateComponents([.day], from: now).day else { return nil }
        let daysRemaining = max(1, monthRange.count - dayOfMonth + 1)

        let remaining = totalBudget - totalSpent
        return remaining / daysRemaining
    }
}
