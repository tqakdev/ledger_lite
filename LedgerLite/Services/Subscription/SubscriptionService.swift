import Foundation
import SwiftData
import UserNotifications

/// Owns subscription lifecycle: expense generation for missed billing cycles,
/// and local notification scheduling.
@MainActor
final class SubscriptionService {
    private let subscriptionRepository: SubscriptionRepository
    private let expenseRepository: ExpenseRepository
    private let currencyService: CurrencyService
    private let homeCurrencyCode: String

    init(
        context: ModelContext,
        homeCurrencyCode: String = UserPreferences.homeCurrencyCode,
        currencyService: CurrencyService? = nil
    ) {
        self.subscriptionRepository = SubscriptionRepository(context: context)
        self.expenseRepository = ExpenseRepository(context: context)
        self.homeCurrencyCode = homeCurrencyCode
        self.currencyService = currencyService ?? CurrencyService(context: context)
    }

    // MARK: - Expense generation

    /// For every active subscription whose `nextBillingDate` is strictly before `referenceDate`,
    /// generates one `Expense` per missed cycle and advances `nextBillingDate` until it is
    /// in the future. Safe to call on every app launch — already-generated dates are skipped.
    func generatePendingExpenses(referenceDate: Date = Date.utcToday) async throws {
        let active = try subscriptionRepository.fetchActive()
        for sub in active {
            try await generateExpenses(for: sub, referenceDate: referenceDate)
        }
    }

    // MARK: - Notifications

    /// Requests authorisation (once), then schedules a notification 2 days before
    /// `subscription.nextBillingDate` at 09:00 local time.
    /// Never throws — notification failure must not block subscription saves.
    func scheduleNotification(for subscription: Subscription) async {
        guard subscription.status == .active else {
            removeNotification(for: subscription)
            return
        }
        let granted = await requestNotificationPermission()
        guard granted else {
            AppLogger.subscriptions.info("Notification permission denied — skipping schedule for \(subscription.name)")
            return
        }

        let identifier = Self.notificationIdentifier(for: subscription)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])

        guard let triggerDate = triggerDate(for: subscription.nextBillingDate),
              triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(subscription.name) bills in 2 days")
        content.body = subscription.money.formatted()
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
            AppLogger.subscriptions.info("Notification scheduled for \(subscription.name) at \(triggerDate)")
        } catch {
            AppLogger.subscriptions.error("Notification scheduling failed for \(subscription.name): \(error)")
        }
    }

    func removeNotification(for subscription: Subscription) {
        let identifier = Self.notificationIdentifier(for: subscription)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
        AppLogger.subscriptions.info("Removed notification for \(subscription.name)")
    }

    /// Returns `"sub-<uuid>"` — stable identifier used to update or remove a pending request.
    static func notificationIdentifier(for subscription: Subscription) -> String {
        "sub-\(subscription.id.uuidString)"
    }

    @discardableResult
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            AppLogger.subscriptions.info("Notification permission granted: \(granted)")
            return granted
        } catch {
            AppLogger.subscriptions.error("Notification permission request failed: \(error)")
            return false
        }
    }

    func notificationsAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    // MARK: - Private

    private func generateExpenses(for sub: Subscription, referenceDate: Date) async throws {
        guard sub.nextBillingDate < referenceDate else { return }

        var generated = 0
        while sub.nextBillingDate < referenceDate {
            let billingDate = sub.nextBillingDate

            let rate: Decimal
            let needsRefresh: Bool
            if sub.currencyCode == homeCurrencyCode {
                rate = 1
                needsRefresh = false
            } else {
                if let fetched = try? await currencyService.rate(
                    from: sub.currencyCode, to: homeCurrencyCode, on: billingDate
                ) {
                    rate = fetched
                    needsRefresh = false
                } else {
                    rate = 1
                    needsRefresh = true
                }
            }

            let expense = Expense(
                amountMinor: sub.amountMinor,
                currencyCode: sub.currencyCode,
                exchangeRateToHome: rate,
                homeCurrencyAtEntry: homeCurrencyCode,
                date: billingDate,
                note: sub.notes,
                merchant: sub.name,
                source: .subscription,
                needsRateRefresh: needsRefresh
            )
            expense.category = sub.category
            expense.subscription = sub
            try expenseRepository.add(expense)
            generated += 1

            sub.nextBillingDate = sub.billingCycle.nextDate(after: billingDate)
        }

        if generated > 0 {
            try subscriptionRepository.savePendingChanges()
            AppLogger.subscriptions.info("Generated \(generated) expense(s) for \(sub.name), next billing: \(sub.nextBillingDate)")
        }
    }

    private func triggerDate(for nextBillingDate: Date) -> Date? {
        guard let twoDaysBefore = Calendar.current.date(byAdding: .day, value: -2, to: nextBillingDate) else {
            return nil
        }
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: twoDaysBefore)
    }
}
