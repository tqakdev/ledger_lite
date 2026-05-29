import Foundation
import SwiftData
import CoreSpotlight

enum ExpenseFormMode: Identifiable {
    case add
    case edit(Expense)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let expense): return expense.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .add: return String(localized: "Quick Add")
        case .edit: return String(localized: "Edit Expense")
        }
    }
}

@MainActor
@Observable
final class ExpenseFormViewModel {
    let mode: ExpenseFormMode

    var amountString: String = ""
    var minorUnits: Int = 0
    var currencyCode: String
    var selectedCategory: Category?
    var note: String = ""
    var merchant: String = ""
    var date: Date = .now

    var categories: [Category] = []
    var isSaving = false
    var errorMessage: String?

    // Merchant autocomplete
    var merchantSuggestions: [String] = []
    private var recentMerchants: [String] = []
    private var recentMerchantCategories: [(merchant: String, categoryName: String)] = []

    // Recurring templates
    var templates: [ExpenseTemplate] = []

    // Receipt scan
    /// Set when a scan couldn't confidently read the amount, so the form can
    /// prompt the user to double-check it.
    var scanLowConfidence = false
    /// How this entry originated; `.scanned` once a receipt has been applied.
    private var source: ExpenseSource = .manual

    private let expenseRepository: ExpenseRepository
    private let categoryRepository: CategoryRepository
    private let currencyService: CurrencyService
    private let homeCurrencyCode: String

    var canSave: Bool {
        minorUnits > 0 && selectedCategory != nil && !isSaving
    }

    init(
        mode: ExpenseFormMode,
        context: ModelContext,
        homeCurrencyCode: String = UserPreferences.homeCurrencyCode
    ) {
        self.mode = mode
        self.homeCurrencyCode = homeCurrencyCode
        self.currencyCode = homeCurrencyCode
        self.expenseRepository = ExpenseRepository(context: context)
        self.categoryRepository = CategoryRepository(context: context)
        self.currencyService = CurrencyService(context: context)

        if case .edit(let expense) = mode {
            minorUnits = expense.amountMinor
            currencyCode = expense.currencyCode
            selectedCategory = expense.category
            note = expense.note ?? ""
            merchant = expense.merchant ?? ""
            date = expense.date
            amountString = AmountInputParser(currencyCode: expense.currencyCode, locale: .current)
                .format(minorUnits: expense.amountMinor)
        }
    }

    func loadCategories() {
        do {
            categories = try categoryRepository.fetchAll()
            if selectedCategory == nil {
                selectedCategory = categories.first(where: { $0.name == "Other" }) ?? categories.first
            }
            loadRecentMerchants()
            templates = ExpenseTemplateService.load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Merchant autocomplete

    func updateMerchantSuggestions(prefix: String) {
        guard !prefix.isEmpty else { merchantSuggestions = []; return }
        let lower = prefix.lowercased()
        var seen = Set<String>()
        merchantSuggestions = recentMerchants
            .filter { $0.lowercased().hasPrefix(lower) && $0.lowercased() != lower }
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Templates

    func applyTemplate(_ template: ExpenseTemplate) {
        merchant = template.merchantName
        note = template.note
        currencyCode = template.currencyCode
        minorUnits = template.amountMinor
        amountString = AmountInputParser(currencyCode: template.currencyCode, locale: .current)
            .format(minorUnits: template.amountMinor)
        if let cat = categories.first(where: { $0.name == template.categoryName }) {
            selectedCategory = cat
        }
    }

    // MARK: - Receipt scan

    /// Pre-fills the form from a scanned receipt. Confident amounts are filled;
    /// an unread amount is left blank and flagged. The category is guessed from
    /// the user's own history first, then a keyword fallback.
    func applyParsedReceipt(_ receipt: ParsedReceipt) {
        source = .scanned

        if let code = receipt.currencyCode, Constants.App.supportedCurrencies.contains(code) {
            currencyCode = code
        }
        if let merchant = receipt.merchant {
            self.merchant = merchant
        }
        if let date = receipt.date {
            self.date = date
        }

        if receipt.amountConfident, let amount = receipt.amountMinor {
            minorUnits = amount
            amountString = AmountInputParser(currencyCode: currencyCode, locale: .current)
                .format(minorUnits: amount)
            scanLowConfidence = false
        } else {
            // Don't pre-fill a number we're unsure of — leave it for the user.
            scanLowConfidence = true
        }

        if let merchant = receipt.merchant, !merchant.isEmpty {
            let available = Set(categories.map(\.name))
            if let guessed = MerchantCategoryGuesser.guess(
                merchant: merchant,
                history: recentMerchantCategories,
                available: available
            ), let cat = categories.first(where: { $0.name == guessed }) {
                selectedCategory = cat
            }
        }
    }

    func saveAsTemplate() {
        guard !merchant.isEmpty, minorUnits > 0 else { return }
        ExpenseTemplateService.add(ExpenseTemplate(
            merchantName: merchant,
            amountMinor: minorUnits,
            currencyCode: currencyCode,
            categoryName: selectedCategory?.name ?? "",
            note: note
        ))
        templates = ExpenseTemplateService.load()
    }

    /// Parses a raw TextField string, updates `amountString` (sanitized) and `minorUnits`.
    func setAmount(_ raw: String) {
        let (display, units) = AmountInputParser(currencyCode: currencyCode, locale: .current).parse(raw)
        amountString = display
        minorUnits = units
    }

    func formattedAmount(locale: Locale = .current) -> String {
        Money(minorUnits: minorUnits, currencyCode: currencyCode).formatted(locale: locale)
    }

    func save() async -> Bool {
        guard canSave, let category = selectedCategory else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            switch mode {
            case .add:
                try await addExpense(category: category)
            case .edit(let expense):
                try await updateExpense(expense, category: category)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.ui.error("Expense save failed: \(error)")
            return false
        }
    }

    // MARK: - Private

    private func loadRecentMerchants() {
        let recent = (try? expenseRepository.fetchRecent(limit: 500)) ?? []
        var seen = Set<String>()
        recentMerchants = recent
            .compactMap { $0.merchant }
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(200)
            .map { $0 }

        // Most-recent (merchant, category) pairs power the scan category guess.
        var seenPairs = Set<String>()
        recentMerchantCategories = recent.compactMap { expense in
            guard let merchant = expense.merchant, let category = expense.category else { return nil }
            guard seenPairs.insert(merchant.lowercased()).inserted else { return nil }
            return (merchant: merchant, categoryName: category.name)
        }
    }

    private func addExpense(category: Category) async throws {
        var exchangeRate = Decimal(1)
        var needsRefresh = false

        if currencyCode != homeCurrencyCode {
            await prefetchRates()
            do {
                exchangeRate = try await currencyService.rate(
                    from: currencyCode,
                    to: homeCurrencyCode,
                    on: date
                )
            } catch {
                exchangeRate = 1
                needsRefresh = true
            }
        }

        let expense = Expense(
            amountMinor: minorUnits,
            currencyCode: currencyCode,
            exchangeRateToHome: exchangeRate,
            homeCurrencyAtEntry: homeCurrencyCode,
            date: date,
            note: note.isEmpty ? nil : note,
            merchant: merchant.isEmpty ? nil : merchant,
            source: source,
            needsRateRefresh: needsRefresh
        )
        expense.category = category
        try expenseRepository.add(expense)
        SpotlightService.index(expense)
        AppLogger.ui.info("Added expense \(self.minorUnits) \(self.currencyCode)")
    }

    private func updateExpense(_ expense: Expense, category: Category) async throws {
        expense.amountMinor = minorUnits
        expense.category = category
        expense.note = note.isEmpty ? nil : note
        expense.merchant = merchant.isEmpty ? nil : merchant
        expense.date = date
        try expenseRepository.update(expense)
        SpotlightService.index(expense)
        AppLogger.ui.info("Updated expense \(expense.id)")
    }

    private func prefetchRates() async {
        try? await currencyService.ensureTodayRates(for: [currencyCode, homeCurrencyCode])
    }
}
