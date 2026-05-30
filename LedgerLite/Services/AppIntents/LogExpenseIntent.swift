import AppIntents
import SwiftData

/// "Log an expense" — available via Siri and Shortcuts.
/// Example: "Hey Siri, log $15 food in LedgerLite"
struct LogExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Expense"
    static var description = IntentDescription("Quickly log an expense in LedgerLite.")

    @Parameter(title: "Amount", description: "Amount in your home currency")
    var amount: Double  // AppIntents requires Double for currency parameters

    @Parameter(title: "Category", description: "Expense category", optionsProvider: CategoryOptionsProvider())
    var categoryName: String?

    @Parameter(title: "Merchant", description: "Where did you spend?")
    var merchant: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) in \(\.$categoryName)") {
            \.$merchant
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.enes.ledgerlite")
        else {
            throw AppIntentError.generic(String(localized: "Could not access Ledger Lite data."))
        }

        let schema = Schema([Expense.self, Subscription.self, Category.self, ExchangeRateCache.self])
        let config = ModelConfiguration(
            schema: schema,
            url: groupURL.appendingPathComponent("LedgerLite.store"),
            cloudKitDatabase: .none
        )
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            throw AppIntentError.generic(String(localized: "Could not open Ledger Lite database."))
        }

        let context = container.mainContext
        let homeCurrency = UserPreferences.homeCurrencyCode
        let places = Money.decimals(for: homeCurrency)

        // AppIntents passes amount as Double — the only Double-money usage in the codebase.
        // Converted immediately and safely to minor units via rounding.
        let minorUnits = Int((amount * pow(10.0, Double(places))).rounded())
        guard minorUnits > 0 else {
            throw AppIntentError.generic(String(localized: "Amount must be greater than zero."))
        }

        // Find matching category, fall back to "Other"
        var category: Category?
        if let name = categoryName {
            let all = (try? context.fetch(FetchDescriptor<Category>())) ?? []
            category = all.first(where: { $0.name.lowercased() == name.lowercased() })
                ?? all.first(where: { $0.name == "Other" })
        }

        let expense = Expense(
            amountMinor: minorUnits,
            currencyCode: homeCurrency,
            exchangeRateToHome: 1,
            homeCurrencyAtEntry: homeCurrency,
            date: .now,
            merchant: merchant,
            source: .siri
        )
        expense.category = category
        context.insert(expense)
        try context.save()

        let formatted = Money(minorUnits: minorUnits, currencyCode: homeCurrency).formatted()
        let catName = category?.name ?? String(localized: "Other")
        return .result(dialog: IntentDialog("Logged \(formatted) in \(catName)."))
    }
}

struct CategoryOptionsProvider: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> [String] {
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.enes.ledgerlite")
        else { return [] }
        let schema = Schema([Expense.self, Subscription.self, Category.self, ExchangeRateCache.self])
        let config = ModelConfiguration(
            schema: schema,
            url: groupURL.appendingPathComponent("LedgerLite.store"),
            cloudKitDatabase: .none
        )
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else { return [] }
        let cats = (try? container.mainContext.fetch(FetchDescriptor<Category>())) ?? []
        return cats.map(\.name)
    }
}

enum AppIntentError: Error, LocalizedError {
    case generic(String)
    var errorDescription: String? {
        switch self { case .generic(let msg): return msg }
    }
}
