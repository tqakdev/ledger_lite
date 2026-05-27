import Foundation
import SwiftData

enum SubscriptionsDestination: Identifiable {
    case add
    case edit(Subscription)
    case autoDetect

    var id: String {
        switch self {
        case .add:           return "add"
        case .edit(let sub): return "edit-\(sub.id.uuidString)"
        case .autoDetect:    return "autoDetect"
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
    var destination: SubscriptionsDestination?
    var errorMessage: String?
    var notificationsAuthorized: Bool = true

    var subscriptionHomeAmounts: [UUID: Int] = [:]

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
            advanceOverdueBillingDates()
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

    private func advanceOverdueBillingDates() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for sub in subscriptions where sub.status == .active && sub.nextBillingDate < today {
            var next = sub.nextBillingDate
            while next < today {
                switch sub.billingCycle {
                case .weekly:           next = cal.date(byAdding: .day,   value: 7,  to: next) ?? next
                case .monthly:          next = cal.date(byAdding: .month, value: 1,  to: next) ?? next
                case .yearly:           next = cal.date(byAdding: .year,  value: 1,  to: next) ?? next
                case .customDays(let n): next = cal.date(byAdding: .day,  value: n,  to: next) ?? next
                }
            }
            sub.nextBillingDate = next
            try? subscriptionRepository.update(sub)
        }
    }

    // MARK: - Monthly cost

    /// Groups active subscriptions by currency, sums each group's monthly equivalent,
    /// then converts each group total to home currency once — avoids per-row rounding drift.
    /// Also populates `subscriptionHomeAmounts` for all foreign-currency subscriptions.
    private func computeMonthlyCost() async {
        monthlyCostIsLoading = true
        defer { monthlyCostIsLoading = false }

        let today = Date.utcToday
        var totalHomeMinor = 0

        // Monthly cost (active only)
        let active = activeSubscriptions
        if !active.isEmpty {
            let grouped = Dictionary(grouping: active, by: \.currencyCode)
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
        }
        monthlyCostMinor = totalHomeMinor

        // Per-subscription home amounts for all foreign-currency subscriptions
        var homeAmounts: [UUID: Int] = [:]
        let foreignSubs = subscriptions.filter { $0.currencyCode != homeCurrencyCode }
        if !foreignSubs.isEmpty {
            let foreignGrouped = Dictionary(grouping: foreignSubs, by: \.currencyCode)
            for (currency, subs) in foreignGrouped {
                do {
                    let rate = try await currencyService.rate(from: currency, to: homeCurrencyCode, on: today)
                    for sub in subs {
                        let converted = Money(minorUnits: sub.amountMinor, currencyCode: currency)
                            .converted(to: homeCurrencyCode, rate: rate)
                        homeAmounts[sub.id] = converted.minorUnits
                    }
                } catch {
                    AppLogger.subscriptions.warning("Rate unavailable for home amounts (\(currency)→\(self.homeCurrencyCode)): \(error)")
                }
            }
        }
        subscriptionHomeAmounts = homeAmounts
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

    // MARK: - Navigation

    func presentAdd() { destination = .add }
    func presentEdit(_ sub: Subscription) { destination = .edit(sub) }
    func presentAutoDetect() { destination = .autoDetect }
    func dismissDestination() { destination = nil; refresh() }

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
