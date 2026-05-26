import Foundation
import SwiftData

@MainActor
final class CurrencyService {
    private let cacheRepository: ExchangeRateCacheRepository
    private let expenseRepository: ExpenseRepository
    private let primary: RateFetching
    private let fallback: RateFetching

    init(
        context: ModelContext,
        primary: RateFetching = FrankfurterClient(),
        fallback: RateFetching = OpenERAPIClient()
    ) {
        self.cacheRepository = ExchangeRateCacheRepository(context: context)
        self.expenseRepository = ExpenseRepository(context: context)
        self.primary = primary
        self.fallback = fallback
    }

    // MARK: - Public API

    func supportedCurrencies() -> [String] {
        Constants.App.supportedCurrencies
    }

    /// Fetches and caches today's EUR→X rates for the given currencies.
    /// Idempotent: skips the network when today's rates are already cached.
    func ensureTodayRates(for currencies: [String]) async throws {
        let codes = Set(currencies).union(["EUR"])
        let today = Date.utcToday
        guard try !cacheRepository.hasEURRates(for: codes, on: today) else { return }
        let quotes = Array(codes).filter { $0 != "EUR" }
        try await fetchAndCacheEURRates(quotes: quotes, on: today)
    }

    /// Returns the exchange rate: 1 unit of `from` = result units of `to` on `date`.
    func rate(from: String, to: String, on date: Date) async throws -> Decimal {
        let normalizedDate = date.utcStartOfDay
        if from == to { return 1 }

        if let direct = try cacheRepository.cachedRate(base: from, quote: to, on: normalizedDate) {
            return direct.rate
        }

        let eurToFrom = try await eurRate(for: from, on: normalizedDate)
        let eurToTo = try await eurRate(for: to, on: normalizedDate)
        return try crossRate(eurToQuote: eurToTo, eurToBase: eurToFrom)
    }

    /// Converts `money` to `targetCode` using the rate on `date`.
    ///
    /// Phase 6 note: Insights aggregations must sum in source currency and convert once at the end.
    /// Do not sum many per-row `converted` values — rounding drift accumulates.
    func convert(_ money: Money, to targetCode: String, on date: Date) async throws -> Money {
        let exchangeRate = try await rate(from: money.currencyCode, to: targetCode, on: date)
        return money.converted(to: targetCode, rate: exchangeRate)
    }

    /// Finds expenses saved with `needsRateRefresh == true` and patches live rates once available.
    func rehydrateStaleRates() async throws {
        let stale = try expenseRepository.fetchNeedingRateRefresh()
        guard !stale.isEmpty else { return }

        for expense in stale {
            let liveRate = try await rate(
                from: expense.currencyCode,
                to: expense.homeCurrencyAtEntry,
                on: expense.date
            )
            expense.exchangeRateToHome = liveRate
            expense.needsRateRefresh = false
        }
        try expenseRepository.savePendingChanges()
        AppLogger.currency.info("Rehydrated \(stale.count) stale expense rate(s)")
    }

    // MARK: - EUR pivot

    private func eurRate(for currency: String, on date: Date) async throws -> Decimal {
        if currency == "EUR" { return 1 }
        if let cached = try cacheRepository.cachedRate(base: "EUR", quote: currency, on: date) {
            return cached.rate
        }
        try await fetchAndCacheEURRates(quotes: [currency], on: date)
        if let cached = try cacheRepository.cachedRate(base: "EUR", quote: currency, on: date) {
            return cached.rate
        }
        throw CurrencyError.rateNotFound(from: "EUR", to: currency, date: date)
    }

    private func crossRate(eurToQuote: Decimal, eurToBase: Decimal) throws -> Decimal {
        guard eurToBase != 0 else { throw CurrencyError.decodingFailed }
        return eurToQuote / eurToBase
    }

    // MARK: - Fetch + cache

    private func fetchAndCacheEURRates(quotes: [String], on date: Date) async throws {
        let uniqueQuotes = Array(Set(quotes).filter { $0 != "EUR" })
        guard !uniqueQuotes.isEmpty else { return }

        let rates: [String: Decimal]
        do {
            rates = try await primary.fetchRates(base: "EUR", quotes: uniqueQuotes, on: date)
        } catch let error as CurrencyError where shouldTryFallback(error) {
            AppLogger.currency.info("Primary failed (\(String(describing: error))) — trying fallback")
            rates = try await fallback.fetchRates(base: "EUR", quotes: uniqueQuotes, on: date)
        } catch {
            if error.isNetworkUnavailable {
                if try allEURQuotesCached(uniqueQuotes, on: date) { return }
                throw CurrencyError.networkUnavailable
            }
            throw error
        }

        try cacheEURRates(rates, on: date)
    }

    private func shouldTryFallback(_ error: CurrencyError) -> Bool {
        switch error {
        case .unsupportedCurrency, .decodingFailed, .rateNotFound:
            return true
        case .networkUnavailable:
            return false
        }
    }

    private func allEURQuotesCached(_ quotes: [String], on date: Date) throws -> Bool {
        for quote in quotes {
            if try cacheRepository.cachedRate(base: "EUR", quote: quote, on: date) == nil {
                return false
            }
        }
        return true
    }

    private func cacheEURRates(_ rates: [String: Decimal], on date: Date) throws {
        for (quote, rate) in rates {
            _ = try cacheRepository.insertIfAbsent(
                base: "EUR",
                quote: quote,
                rate: rate,
                rateDate: date
            )
        }
    }
}
