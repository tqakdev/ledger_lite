import Foundation
import SwiftData

enum SubscriptionFormMode: Identifiable {
    case add
    case edit(Subscription)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let sub): return sub.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .add: return String(localized: "Add Subscription")
        case .edit: return String(localized: "Edit Subscription")
        }
    }
}

@MainActor
@Observable
final class SubscriptionFormViewModel {
    let mode: SubscriptionFormMode

    var name: String = ""
    var amountString: String = ""
    var minorUnits: Int = 0
    var currencyCode: String
    var billingCycle: BillingCycle = .monthly
    var customDays: String = "30"
    var nextBillingDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    var selectedCategory: Category?
    var notes: String = ""

    var categories: [Category] = []
    var isSaving: Bool = false
    var errorMessage: String?

    private let subscriptionRepository: SubscriptionRepository
    private let categoryRepository: CategoryRepository
    private let subscriptionService: SubscriptionService
    private let homeCurrencyCode: String

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && minorUnits > 0 && !isSaving
    }

    /// The BillingCycle to actually persist: resolves .customDays from the `customDays` text field.
    var resolvedBillingCycle: BillingCycle {
        switch billingCycle {
        case .customDays:
            let n = Int(customDays) ?? 30
            return .customDays(max(1, n))
        default:
            return billingCycle
        }
    }

    init(
        mode: SubscriptionFormMode,
        context: ModelContext,
        homeCurrencyCode: String = UserPreferences.homeCurrencyCode
    ) {
        self.mode = mode
        self.homeCurrencyCode = homeCurrencyCode
        self.currencyCode = homeCurrencyCode
        self.subscriptionRepository = SubscriptionRepository(context: context)
        self.categoryRepository = CategoryRepository(context: context)
        self.subscriptionService = SubscriptionService(context: context)

        if case .edit(let sub) = mode {
            name = sub.name
            minorUnits = sub.amountMinor
            currencyCode = sub.currencyCode
            billingCycle = sub.billingCycle
            if case .customDays(let n) = sub.billingCycle { customDays = "\(n)" }
            nextBillingDate = sub.nextBillingDate
            selectedCategory = sub.category
            notes = sub.notes ?? ""
            amountString = AmountInputParser(currencyCode: sub.currencyCode, locale: .current)
                .format(minorUnits: sub.amountMinor)
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

    func setAmount(_ raw: String) {
        let (display, units) = AmountInputParser(currencyCode: currencyCode, locale: .current).parse(raw)
        amountString = display
        minorUnits = units
    }

    func setCurrency(_ code: String) {
        currencyCode = code
        setAmount("")
    }

    // MARK: - Save

    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            switch mode {
            case .add:
                try await addSubscription()
            case .edit(let sub):
                try await updateSubscription(sub)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.subscriptions.error("Subscription save failed: \(error)")
            return false
        }
    }

    // MARK: - Private

    private func addSubscription() async throws {
        let sub = Subscription(
            name: name.trimmingCharacters(in: .whitespaces),
            amountMinor: minorUnits,
            currencyCode: currencyCode,
            billingCycle: resolvedBillingCycle,
            nextBillingDate: nextBillingDate,
            notes: notes.isEmpty ? nil : notes
        )
        sub.category = selectedCategory
        try subscriptionRepository.add(sub)
        AppLogger.subscriptions.info("Created subscription \(sub.name)")

        // Generate any missed expenses if the billing date is already in the past
        try await subscriptionService.generatePendingExpenses()
        await subscriptionService.scheduleNotification(for: sub)
    }

    private func updateSubscription(_ sub: Subscription) async throws {
        sub.name = name.trimmingCharacters(in: .whitespaces)
        sub.amountMinor = minorUnits
        sub.currencyCode = currencyCode
        sub.billingCycle = resolvedBillingCycle
        sub.nextBillingDate = nextBillingDate
        sub.category = selectedCategory
        sub.notes = notes.isEmpty ? nil : notes
        try subscriptionRepository.update(sub)
        AppLogger.subscriptions.info("Updated subscription \(sub.name)")

        try await subscriptionService.generatePendingExpenses()
        await subscriptionService.scheduleNotification(for: sub)
    }
}
