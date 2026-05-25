#if DEBUG
import SwiftData
import Foundation

/// In-memory ModelContainer with deterministic sample data for SwiftUI previews.
/// Uses a frozen "now" so previews never drift and snapshot tests stay reproducible.
@MainActor
enum PreviewContainer {
    /// 2026-01-01 00:00:00 UTC — frozen reference point for all preview dates.
    static let frozenNow = Date(timeIntervalSince1970: 1_735_689_600)

    static let shared: ModelContainer = {
        do {
            let schema = Schema([
                Expense.self,
                Subscription.self,
                Category.self,
                ExchangeRateCache.self,
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            populate(context: container.mainContext)
            return container
        } catch {
            fatalError("PreviewContainer init failed: \(error)")
        }
    }()

    // MARK: - Population

    private static func populate(context: ModelContext) {
        let food      = makeCategory("Food",      icon: "fork.knife",          hex: "#FF6B35", order: 0)
        let transport = makeCategory("Transport", icon: "car.fill",             hex: "#4ECDC4", order: 1)
        let other     = makeCategory("Other",     icon: "square.grid.2x2.fill", hex: "#BDC3C7", order: 9)

        for cat in [food, transport, other] { context.insert(cat) }

        // 5 expenses: 3 USD same day, 1 EUR yesterday, 1 JPY two days ago
        let expenses: [Expense] = [
            {
                let e = Expense(amountMinor: 1250, currencyCode: "USD",
                                exchangeRateToHome: 1, homeCurrencyAtEntry: "USD",
                                date: frozenNow, note: "Lunch", source: .manual)
                e.category = food
                return e
            }(),
            {
                let e = Expense(amountMinor: 450, currencyCode: "USD",
                                exchangeRateToHome: 1, homeCurrencyAtEntry: "USD",
                                date: frozenNow.addingTimeInterval(-3_600), note: "Coffee", source: .manual)
                e.category = food
                return e
            }(),
            {
                let e = Expense(amountMinor: 2800, currencyCode: "USD",
                                exchangeRateToHome: 1, homeCurrencyAtEntry: "USD",
                                date: frozenNow.addingTimeInterval(-7_200), note: "Groceries", source: .manual)
                e.category = other
                return e
            }(),
            {
                let e = Expense(amountMinor: 1500, currencyCode: "EUR",
                                exchangeRateToHome: Decimal(safeString: "1.08"),
                                homeCurrencyAtEntry: "USD",
                                date: frozenNow.addingTimeInterval(-86_400), note: "Dinner", source: .manual)
                e.category = food
                return e
            }(),
            {
                let e = Expense(amountMinor: 1800, currencyCode: "JPY",
                                exchangeRateToHome: Decimal(safeString: "0.0067"),
                                homeCurrencyAtEntry: "USD",
                                date: frozenNow.addingTimeInterval(-172_800), note: "Metro", source: .manual)
                e.category = transport
                return e
            }(),
        ]
        for e in expenses { context.insert(e) }

        // 2 active subscriptions
        let spotify = Subscription(name: "Spotify", amountMinor: 999, currencyCode: "USD",
                                   billingCycle: .monthly,
                                   nextBillingDate: frozenNow.addingTimeInterval(86_400 * 12))
        spotify.category = other

        let netflix = Subscription(name: "Netflix", amountMinor: 1599, currencyCode: "USD",
                                   billingCycle: .monthly,
                                   nextBillingDate: frozenNow.addingTimeInterval(86_400 * 3))
        netflix.category = other

        context.insert(spotify)
        context.insert(netflix)
    }

    private static func makeCategory(_ name: String, icon: String, hex: String, order: Int) -> Category {
        Category(name: name, iconName: icon, colorHex: hex, sortOrder: order, isSystem: true)
    }
}
#endif
