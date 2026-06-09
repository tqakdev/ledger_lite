import Foundation
import SwiftData

/// Builds the inputs for `RunwayForecast` from on-device data and exposes the result
/// to the Runway card and detail screen.
///
/// All inputs come from the device: the user's entered balance + payday, their active
/// subscriptions (future bills), and their recent non-subscription spending rate. Nothing
/// is read from a bank — that constraint is the whole point of the feature.
@MainActor
@Observable
final class ForecastViewModel {

    // MARK: - Outputs

    /// nil until the user has set both a balance and a payday.
    var result: RunwayForecast.Result?
    /// The last inputs fed to the engine — available for what-if re-projection in the UI.
    private(set) var lastInput: RunwayForecast.Input?
    var homeCurrencyCode: String = UserPreferences.homeCurrencyCode
    var hasSetup: Bool = UserPreferences.hasRunwaySetup
    /// True when the configured payday is in the past. Projecting beyond it would be
    /// meaningless, so the UI swaps the forecast for an "update your runway" prompt.
    private(set) var paydayPassed = false

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let rateCache: ExchangeRateCacheRepository

    init(context: ModelContext) {
        self.modelContext = context
        self.rateCache = ExchangeRateCacheRepository(context: context)
    }

    // MARK: - Refresh

    func refresh(now: Date = Date()) {
        homeCurrencyCode = UserPreferences.homeCurrencyCode
        hasSetup = UserPreferences.hasRunwaySetup

        guard let balanceMinor = UserPreferences.availableBalanceMinor,
              let payday = UserPreferences.nextPayday else {
            result = nil
            paydayPassed = false
            return
        }

        let cal = Calendar.current
        if cal.startOfDay(for: payday) < cal.startOfDay(for: now) {
            paydayPassed = true
            result = nil
            lastInput = nil
            UserPreferences.cachedSafeToSpendMinor = nil
            return
        }
        paydayPassed = false

        let asOf = UserPreferences.balanceAsOfDate ?? now

        let effectiveBalance = balanceMinor - spentSince(asOf, now: now)
        let bills = upcomingBills(now: now, payday: payday)
        let discretionary = projectedDailyDiscretionary(now: now)

        let input = RunwayForecast.Input(
            startingBalanceMinor: effectiveBalance,
            today: now,
            payday: payday,
            bills: bills,
            projectedDailyDiscretionaryMinor: discretionary
        )
        lastInput = input
        result = RunwayForecast.project(input)
        UserPreferences.cachedSafeToSpendMinor = result?.trulySafePerDayMinor
    }

    // MARK: - Input builders

    /// Home-currency total of expenses logged strictly after `asOf` and not after `now`.
    /// Subtracted from the entered balance so the runway stays honest between balance updates.
    private func spentSince(_ asOf: Date, now: Date) -> Int {
        let fetched = (try? modelContext.fetch(
            FetchDescriptor<Expense>(
                predicate: #Predicate { $0.date > asOf && $0.date <= now },
                sortBy: []
            )
        )) ?? []
        return fetched.totalInHomeCurrency(homeCurrencyCode)
    }

    /// Expands every active subscription into its billing dates in (now, payday].
    /// A weekly sub may contribute several bills; the loop is capped defensively.
    private func upcomingBills(now: Date, payday: Date) -> [RunwayForecast.Bill] {
        let active = (try? modelContext.fetch(
            FetchDescriptor<Subscription>(
                predicate: #Predicate { $0.statusRaw == "active" },
                sortBy: [SortDescriptor(\.nextBillingDate)]
            )
        )) ?? []

        var bills: [RunwayForecast.Bill] = []
        let cal = Calendar.current
        let paydayDay = cal.startOfDay(for: payday)

        for sub in active {
            var billingDate = sub.nextBillingDate
            var iterations = 0
            while cal.startOfDay(for: billingDate) <= paydayDay {
                iterations += 1
                guard iterations <= 200 else { break }
                if billingDate > now {
                    bills.append(
                        RunwayForecast.Bill(
                            date: billingDate,
                            amountMinor: homeAmountMinor(for: sub, on: billingDate),
                            name: sub.name
                        )
                    )
                }
                billingDate = sub.billingCycle.nextDate(after: billingDate)
            }
        }
        return bills
    }

    /// Average daily non-subscription spend over the last 30 days, in home currency.
    /// Subscriptions are excluded here because they are already modelled as discrete bills.
    private func projectedDailyDiscretionary(now: Date) -> Int {
        guard let since = Calendar.current.date(byAdding: .day, value: -30, to: now) else { return 0 }
        let recent = (try? modelContext.fetch(
            FetchDescriptor<Expense>(
                predicate: #Predicate { $0.date >= since && $0.date <= now },
                sortBy: []
            )
        )) ?? []
        let discretionary = recent.filter { $0.sourceRaw != ExpenseSource.subscription.rawValue }
        guard !discretionary.isEmpty else { return 0 }
        return discretionary.totalInHomeCurrency(homeCurrencyCode) / 30
    }

    // MARK: - Currency

    /// Best-effort conversion of a subscription amount to home-currency minor units.
    /// Same currency is exact; otherwise a cached EUR-pivot cross rate is used when present,
    /// falling back to the face amount (most users are single-currency).
    private func homeAmountMinor(for sub: Subscription, on date: Date) -> Int {
        let home = homeCurrencyCode
        if sub.currencyCode == home { return sub.amountMinor }
        guard let rate = cachedCrossRate(from: sub.currencyCode, to: home, on: date) else {
            return sub.amountMinor
        }
        return sub.money.converted(to: home, rate: rate).minorUnits
    }

    /// Reads a cross rate from the local cache only — no network. Returns nil if either
    /// EUR leg is missing for `date`.
    private func cachedCrossRate(from: String, to: String, on date: Date) -> Decimal? {
        guard let eurToFrom = cachedEURRate(for: from, on: date),
              let eurToTo = cachedEURRate(for: to, on: date),
              eurToFrom != 0 else { return nil }
        return eurToTo / eurToFrom
    }

    private func cachedEURRate(for currency: String, on date: Date) -> Decimal? {
        if currency == "EUR" { return 1 }
        return (try? rateCache.cachedRate(base: "EUR", quote: currency, on: date))?.rate
    }

    // MARK: - Setup persistence

    /// Persists a new balance + payday and immediately recomputes the runway.
    func saveSetup(balanceMinor: Int, payday: Date, now: Date = Date()) {
        UserPreferences.availableBalanceMinor = balanceMinor
        UserPreferences.balanceAsOfDate = now
        UserPreferences.nextPayday = payday
        refresh(now: now)
    }

    /// Clears all runway inputs and hides the feature.
    func clearSetup() {
        UserPreferences.availableBalanceMinor = nil
        UserPreferences.balanceAsOfDate = nil
        UserPreferences.nextPayday = nil
        UserPreferences.paydayIncomeMinor = nil
        UserPreferences.cachedSafeToSpendMinor = nil
        lastInput = nil
        refresh()
    }
}
