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

    init?() {
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.enes.ledgerlite")
        else { return nil }
        let storeURL = groupURL.appendingPathComponent("LedgerLite.store")
        let schema = Schema([Expense.self, Subscription.self, Category.self, ExchangeRateCache.self])
        let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        guard let c = try? ModelContainer(for: schema, configurations: [config]) else { return nil }
        self.container = c
    }

    // MARK: - Public API

    @MainActor
    func todaySummary() -> TodaySummary {
        let context = container.mainContext
        let homeCurrency = UserDefaults(suiteName: "group.com.enes.ledgerlite")?
            .string(forKey: "homeCurrencyCode") ?? "USD"
        let start = Calendar.current.startOfDay(for: Date())
        let end   = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start

        let descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let expenses = (try? context.fetch(descriptor)) ?? []

        let homePlaces = Money.decimals(for: homeCurrency)
        var accumulated = Decimal(0)
        for e in expenses {
            if e.currencyCode == e.homeCurrencyAtEntry {
                accumulated += Decimal(e.amountMinor)
            } else {
                accumulated += e.money.decimalValue * e.exchangeRateToHome
                    * Decimal.powerOfTen(homePlaces)
            }
        }
        var rounded = Decimal()
        var acc = accumulated
        NSDecimalRound(&rounded, &acc, 0, .plain)
        let totalMinor = NSDecimalNumber(decimal: rounded).intValue

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
