import Foundation
import SwiftData

/// Synchronous, actor-free data reader for the widget and App Intents.
/// Opens the shared App Group SwiftData store (same URL as the main app).
/// Never call from the main app's UI layer — use ExpenseRepository there.
struct WidgetDataService {
    private let container: ModelContainer

    // MARK: - Nested types

    struct TodaySummary {
        let totalMinor: Int
        let currencyCode: String
        let expenses: [ExpenseSnapshot]
    }

    struct ExpenseSnapshot: Identifiable {
        let id: UUID
        let amountMinor: Int
        let currencyCode: String
        let homeCurrencyCode: String
        let exchangeRateToHome: Decimal
        let merchant: String?
        let note: String?
        let categoryName: String?
        let categoryColorHex: String?
        let categoryIconName: String?
        let date: Date
    }

    struct SubscriptionSnapshot: Identifiable {
        let id: UUID
        let name: String
        let amountMinor: Int
        let currencyCode: String
        let nextBillingDate: Date
        let categoryColorHex: String?
    }

    // MARK: - Init

    /// Opening a `ModelContainer` is expensive and every widget timeline refresh
    /// constructs a fresh service — share one process-wide container instead.
    /// (`static let` initialization is lazy and thread-safe.)
    private static let sharedContainer: ModelContainer? = {
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Constants.App.appGroupIdentifier)
        else { return nil }
        let storeURL = groupURL.appendingPathComponent("LedgerLite.store")
        let schema = Schema([Expense.self, Subscription.self, Category.self, ExchangeRateCache.self])
        let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        return try? ModelContainer(for: schema, configurations: [config])
    }()

    init?() {
        guard let container = Self.sharedContainer else { return nil }
        self.container = container
    }

    // MARK: - Public API

    @MainActor
    func todaySummary() -> TodaySummary {
        let context = container.mainContext
        let homeCurrency = UserDefaults(suiteName: Constants.App.appGroupIdentifier)?
            .string(forKey: "homeCurrencyCode") ?? "USD"
        let start = Calendar.current.startOfDay(for: Date())
        let end   = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start

        let descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let expenses = (try? context.fetch(descriptor)) ?? []

        let totalMinor = expenses.totalInHomeCurrency(homeCurrency)

        let snapshots = expenses.prefix(3).map { e in
            ExpenseSnapshot(
                id: e.id,
                amountMinor: e.amountMinor,
                currencyCode: e.currencyCode,
                homeCurrencyCode: homeCurrency,
                exchangeRateToHome: e.exchangeRateToHome,
                merchant: e.merchant,
                note: e.note,
                categoryName: e.category?.name,
                categoryColorHex: e.category?.colorHex,
                categoryIconName: e.category?.iconName,
                date: e.date
            )
        }

        return TodaySummary(totalMinor: totalMinor, currencyCode: homeCurrency, expenses: snapshots)
    }

    @MainActor
    func upcomingSubscriptions(limit: Int = 3) -> [SubscriptionSnapshot] {
        let context = container.mainContext
        let descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate { $0.statusRaw == "active" },
            sortBy: [SortDescriptor(\.nextBillingDate)]
        )
        let subs = (try? context.fetch(descriptor)) ?? []
        return subs.prefix(limit).map { s in
            SubscriptionSnapshot(
                id: s.id,
                name: s.name,
                amountMinor: s.amountMinor,
                currencyCode: s.currencyCode,
                nextBillingDate: s.nextBillingDate,
                categoryColorHex: s.category?.colorHex
            )
        }
    }
}
