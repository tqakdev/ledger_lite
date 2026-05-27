import Foundation
import SwiftData

enum SubscriptionSheet: Identifiable {
    case add
    case edit(Subscription)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let sub): return "edit-\(sub.id.uuidString)"
        }
    }

    var formMode: SubscriptionFormMode {
        switch self {
        case .add: return .add
        case .edit(let sub): return .edit(sub)
        }
    }
}

@MainActor
@Observable
final class SubscriptionsViewModel {
    var subscriptions: [Subscription] = []
    var monthlyCostMinor: Int = 0
    var monthlyCostIsLoading: Bool = false
    var homeCurrencyCode: String = UserPreferences.homeCurrencyCode
    var activeSheet: SubscriptionSheet?
    var errorMessage: String?
    var notificationsAuthorized: Bool = true

    var activeSubscriptions: [Subscription] {
        subscriptions.filter { $0.status == .active }
    }

    var inactiveSubscriptions: [Subscription] {
        subscriptions.filter { $0.status != .active }
    }

    private let subscriptionRepository: SubscriptionRepository
    private let currencyService: CurrencyService
    private let subscriptionService: SubscriptionService

    init(context: ModelContext) {
        self.subscriptionRepository = SubscriptionRepository(context: context)
        self.currencyService = CurrencyService(context: context)
        self.subscriptionService = SubscriptionService(context: context)
    }

    // MARK: - Load

    func refresh() {
        homeCurrencyCode = UserPreferences.homeCurrencyCode
        do {
            subscriptions = try subscriptionRepository.fetchAll()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.subscriptions.error("Subscriptions refresh failed: \(error)")
        }
        Task {
            await checkNotificationStatus()
            await computeMonthlyCost()
        }
    }

    // MARK: - Monthly cost

    /// Groups active subscriptions by currency, sums each group's monthly equivalent,
    /// then converts each group total to home currency once — avoids per-row rounding drift.
    private func computeMonthlyCost() async {
        let active = activeSubscriptions
        guard !active.isEmpty else { monthlyCostMinor = 0; return }

        monthlyCostIsLoading = true
        defer { monthlyCostIsLoading = false }

        let grouped = Dictionary(grouping: active, by: \.currencyCode)
        let today = Date.utcToday
        var totalHomeMinor = 0

        for (currency, subs) in grouped {
            let groupMonthly = subs.reduce(0) { $0 + $1.monthlyEquivalentMinorUnits() }

            if currency == homeCurrencyCode {
                totalHomeMinor += groupMonthly
            } else {
                do {
                    let rate = try await currencyService.rate(from: currency, to: homeCurrencyCode, on: today)
                    let converted = Money(minorUnits: groupMonthly, currencyCode: currency)
                        .converted(to: homeCurrencyCode, rate: rate)
                    totalHomeMinor += converted.minorUnits
                } catch {
                    AppLogger.subscriptions.warning("Rate unavailable for monthly cost (\(currency)→\(self.homeCurrencyCode)): \(error)")
                }
            }
        }

        monthlyCostMinor = totalHomeMinor
    }

    // MARK: - Status actions

    func pauseSubscription(_ sub: Subscription) {
        sub.status = .paused
        persistAndRefresh(sub, action: "paused")
        subscriptionService.removeNotification(for: sub)
    }

    func resumeSubscription(_ sub: Subscription) {
        sub.status = .active
        persistAndRefresh(sub, action: "resumed")
        Task { await subscriptionService.scheduleNotification(for: sub) }
    }

    func cancelSubscription(_ sub: Subscription) {
        sub.status = .cancelled
        persistAndRefresh(sub, action: "cancelled")
        subscriptionService.removeNotification(for: sub)
    }

    func deleteSubscription(_ sub: Subscription) {
        subscriptionService.removeNotification(for: sub)
        do {
            try subscriptionRepository.delete(sub)
            refresh()
            AppLogger.subscriptions.info("Deleted subscription \(sub.name)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sheet

    func presentAdd() { activeSheet = .add }
    func presentEdit(_ sub: Subscription) { activeSheet = .edit(sub) }
    func dismissSheet() { activeSheet = nil; refresh() }

    // MARK: - Private

    private func persistAndRefresh(_ sub: Subscription, action: String) {
        do {
            try subscriptionRepository.update(sub)
            refresh()
            AppLogger.subscriptions.info("Subscription \(sub.name) \(action)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func checkNotificationStatus() async {
        notificationsAuthorized = await subscriptionService.notificationsAuthorized()
    }
}
