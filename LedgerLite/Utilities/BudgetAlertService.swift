import Foundation
import UserNotifications
import SwiftData

/// Checks monthly category budgets and fires a one-time local notification
/// when spending crosses the 80% or 100% threshold within a calendar month.
/// Uses UserDefaults to track the highest tier already notified per category
/// per month, so notifications never repeat for the same threshold.
@MainActor
final class BudgetAlertService {
    private let modelContext: ModelContext

    init(context: ModelContext) {
        self.modelContext = context
    }

    func checkBudgets() {
        let cal = Calendar.current
        let now = Date()
        var monthComps = cal.dateComponents([.year, .month], from: now)
        monthComps.day = 1
        guard let monthStart = cal.date(from: monthComps),
              let year = monthComps.year,
              let month = monthComps.month else { return }
        let monthKey = "\(year)-\(month)"

        guard let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { return }
        guard let expenses = try? modelContext.fetch(
            FetchDescriptor<Expense>(
                predicate: #Predicate { $0.date >= monthStart && $0.date < monthEnd },
                sortBy: []
            )
        ) else { return }

        guard let categories = try? modelContext.fetch(FetchDescriptor<Category>()) else { return }

        let homeCurrency = UserPreferences.homeCurrencyCode
        let homePlaces = Money.decimals(for: homeCurrency)

        var spendingByCategory: [UUID: Int] = [:]
        for expense in expenses {
            guard let cat = expense.category else { continue }
            let minor: Int
            if expense.currencyCode == expense.homeCurrencyAtEntry {
                minor = expense.amountMinor
            } else {
                let dec = expense.money.decimalValue * expense.exchangeRateToHome
                              * Decimal.powerOfTen(homePlaces)
                minor = NSDecimalNumber(decimal: dec.rounded(scale: 0)).intValue
            }
            spendingByCategory[cat.id, default: 0] += minor
        }

        for category in categories {
            guard let budget = category.monthlyBudgetMinor, budget > 0 else { continue }
            let spent = spendingByCategory[category.id] ?? 0
            let ratio = Double(spent) / Double(budget)

            let tier: Int
            if ratio >= 1.0      { tier = 100 }
            else if ratio >= 0.8 { tier = 80 }
            else                 { continue }

            let key = "budgetAlert_\(category.id)_\(monthKey)"
            let lastTier = UserDefaults.standard.integer(forKey: key)
            guard tier > lastTier else { continue }
            UserDefaults.standard.set(tier, forKey: key)

            scheduleNotification(category: category, tier: tier,
                                 spent: spent, budget: budget, currency: homeCurrency)
        }
    }

    private func scheduleNotification(category: Category, tier: Int,
                                      spent: Int, budget: Int, currency: String) {
        let content = UNMutableNotificationContent()
        let spentStr  = Money(minorUnits: spent,  currencyCode: currency).formatted()
        let budgetStr = Money(minorUnits: budget, currencyCode: currency).formatted()

        if tier == 100 {
            content.title = String(localized: "\(category.name) budget reached")
            content.body  = String(localized: "You've spent \(spentStr) of your \(budgetStr) budget.")
        } else {
            content.title = String(localized: "\(category.name) at 80% of budget")
            content.body  = String(localized: "\(spentStr) of \(budgetStr) spent this month.")
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "budget-\(category.id)-\(tier)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
}
