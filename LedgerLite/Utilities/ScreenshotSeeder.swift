#if DEBUG
import Foundation
import SwiftData

/// Seeds rich, realistic demo data for App Store screenshots. Runs only when the
/// app is launched with `--seed-screenshots`, never in normal use. Wipes existing
/// expenses/subscriptions first so the captured screens are deterministic.
enum ScreenshotSeeder {

    @MainActor
    static func seed(context: ModelContext) {
        // Skip onboarding and the biometric lock so the main UI is visible.
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(false, forKey: "biometricLockEnabled")
        UserPreferences.homeCurrencyCode = "USD"

        // Seed the Payday Runway. Balance of $1,800 with 14 days to payday keeps
        // the safe-to-spend number in a visually appealing range (~$100/day after bills).
        UserPreferences.availableBalanceMinor = 180_000          // $1,800
        UserPreferences.balanceAsOfDate = Date()
        UserPreferences.nextPayday = Calendar.current.date(byAdding: .day, value: 14, to: Date())

        guard let categories = try? CategoryRepository(context: context).fetchAll() else { return }
        var byName: [String: Category] = [:]
        for category in categories { byName[category.name] = category }

        // Clear any prior data for a clean, repeatable capture.
        for expense in (try? context.fetch(FetchDescriptor<Expense>())) ?? [] { context.delete(expense) }
        for sub in (try? context.fetch(FetchDescriptor<Subscription>())) ?? [] { context.delete(sub) }

        // Monthly budgets → drive the budget progress bars in Trends.
        setBudget(byName["Food"], 40000)
        setBudget(byName["Groceries"], 35000)
        setBudget(byName["Transport"], 15000)
        setBudget(byName["Entertainment"], 10000)
        setBudget(byName["Shopping"], 60000)

        let cal = Calendar.current
        let now = Date()
        func date(_ dayOffset: Int, hour: Int) -> Date {
            let day = cal.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            return cal.date(bySettingHour: hour, minute: 12, second: 0, of: day) ?? day
        }

        // A scanned Nike receipt — used for the receipt-scan screenshot.
        // Moved to 5 days ago so today's total looks normal for the Runway hero.
        let nikeNote = """
        Air Jordan 4 (Men's) x1 — US$489.00
        Premium sneaker cleaner x1 — US$32.99
        Crew socks (2-pack) x2 — US$28.00
        Lace set (extra) x1 — US$14.00
        """

        // (merchant, category, cents, dayOffset, hour, source, note)
        let rows: [(String, String, Int, Int, Int, ExpenseSource, String?)] = [
            // Today — realistic, below the ~$100/day safe number so bar shows healthy
            ("Blue Bottle Coffee",  "Food",            575,  0,  8, .manual,  nil),
            ("Uber",                "Transport",      1420,  0, 18, .manual,  nil),
            ("Whole Foods",         "Groceries",      4230,  0, 19, .manual,  nil),
            // Yesterday
            ("Chipotle",            "Food",           1285,  1, 13, .manual,  nil),
            ("Shell",               "Transport",      4800,  1, 17, .manual,  nil),
            // 2 days ago
            ("Trader Joe's",        "Groceries",      6310,  2, 11, .manual,  nil),
            ("Cinema City",         "Entertainment",  2400,  2, 20, .manual,  nil),
            // 3 days ago
            ("Starbucks",           "Food",            640,  3,  9, .manual,  nil),
            ("Amazon",              "Shopping",       3499,  3, 15, .manual,  nil),
            // 4 days ago
            ("Pharmacy Plus",       "Health",         1875,  4, 10, .manual,  nil),
            ("Pret A Manger",       "Food",            925,  4, 12, .manual,  nil),
            // 5 days ago — scanned Nike receipt
            ("Nike Store",          "Shopping",      56399,  5, 16, .scanned, nikeNote),
            ("Lyft",                "Transport",      1110,  5, 14, .manual,  nil),
            // 6 days ago
            ("Aldi",                "Groceries",      2780,  6, 18, .manual,  nil),
            ("Spotify Merch",       "Shopping",       2200,  6, 16, .manual,  nil),
            // 7 days ago
            ("Sweetgreen",          "Food",           1450,  7, 13, .manual,  nil),
            ("City Transit",        "Transport",       290,  7,  8, .manual,  nil),
            // 8 days ago
            ("Costco",              "Groceries",      8420,  8, 12, .manual,  nil),
            ("Burger Joint",        "Food",           1690,  8, 19, .manual,  nil),
            // 9 days ago
            ("Bookstore",           "Shopping",       1899,  9, 15, .manual,  nil),
            ("Pharmacy Plus",       "Health",          990,  9, 10, .manual,  nil),
        ]

        for (merchant, categoryName, cents, dayOffset, hour, source, note) in rows {
            let expense = Expense(
                amountMinor: cents,
                currencyCode: "USD",
                exchangeRateToHome: 1,
                homeCurrencyAtEntry: "USD",
                date: date(dayOffset, hour: hour),
                note: note,
                merchant: merchant,
                source: source
            )
            expense.category = byName[categoryName]
            context.insert(expense)
        }

        // Subscriptions — provide real upcoming bill dates so they appear on the
        // runway chart as orange markers and in the "Bills before payday" list.
        let subsCat = byName["Subscriptions"]
        let subs: [(String, Int, Int)] = [   // name, cents, days until next bill
            ("Netflix",     1549,  3),
            ("Spotify",     1199,  8),
            ("iCloud+",      299, 12),
            ("ChatGPT Plus", 2000, 20),   // outside 14-day window → not on runway
        ]
        for (name, cents, daysAhead) in subs {
            let next = cal.date(byAdding: .day, value: daysAhead, to: now) ?? now
            let sub = Subscription(
                name: name,
                amountMinor: cents,
                currencyCode: "USD",
                billingCycle: .monthly,
                nextBillingDate: next,
                startedOn: cal.date(byAdding: .month, value: -4, to: now) ?? now,
                status: .active
            )
            sub.category = subsCat
            context.insert(sub)
        }

        try? context.save()

        // Pre-populate the widget cache so the Runway widget shows the right number
        // before ForecastViewModel.refresh() has run. Bills within 14 days: $30.47.
        // Today's expenses: $62.25 → effective balance ≈ $1,737. Safe ≈ $121/day.
        let billsWithin14 = 1549 + 1199 + 299  // Netflix + Spotify + iCloud
        let todaySpent = 575 + 1420 + 4230      // Coffee + Uber + WholeFoods
        let effective = 180_000 - todaySpent
        let approxSafe = (effective - billsWithin14) / 14
        UserPreferences.cachedSafeToSpendMinor = approxSafe

        AppLogger.data.info("Screenshot demo data seeded.")
    }

    private static func setBudget(_ category: Category?, _ minor: Int) {
        category?.monthlyBudgetMinor = minor
    }
}
#endif
