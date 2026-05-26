import Foundation
import SwiftData

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

    var minorUnits: Int = 0
    var currencyCode: String
    var selectedCategory: Category?
    var note: String = ""
    var merchant: String = ""
    var date: Date = .now

    var categories: [Category] = []
    var isSaving = false
    var errorMessage: String?

    private let expenseRepository: ExpenseRepository
    private let categoryRepository: CategoryRepository
    private let currencyService: CurrencyService
    private let homeCurrencyCode: String

    var decimalPlaces: Int { Money.decimals(for: currencyCode) }

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
        }
    }

    func loadCategories() {
        do {
            categories = try categoryRepository.fetchAll()
            if selectedCategory == nil {
                selectedCategory = categories.first(where: { $0.name == "Other" }) ?? categories.first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func appendDigit(_ digit: Int) {
        guard (0...9).contains(digit) else { return }
        let next = minorUnits * 10 + digit
        guard next <= 999_999_999 else { return }
        minorUnits = next
    }

    func deleteLastDigit() {
        minorUnits /= 10
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
            source: .manual,
            needsRateRefresh: needsRefresh
        )
        expense.category = category
        try expenseRepository.add(expense)
        AppLogger.ui.info("Added expense \(self.minorUnits) \(self.currencyCode)")
    }

    private func updateExpense(_ expense: Expense, category: Category) async throws {
        expense.amountMinor = minorUnits
        expense.category = category
        expense.note = note.isEmpty ? nil : note
        expense.merchant = merchant.isEmpty ? nil : merchant
        expense.date = date
        try expenseRepository.update(expense)
        AppLogger.ui.info("Updated expense \(expense.id)")
    }

    private func prefetchRates() async {
        try? await currencyService.ensureTodayRates(for: [currencyCode, homeCurrencyCode])
    }
}
