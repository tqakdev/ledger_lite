import Foundation
import SwiftData

@MainActor
final class ExchangeRateCacheRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func cachedRate(base: String, quote: String, on date: Date) throws -> ExchangeRateCache? {
        let key = ExchangeRateCache.cacheKey(base: base, quote: quote, date: date.utcStartOfDay)
        let descriptor = FetchDescriptor<ExchangeRateCache>(
            predicate: #Predicate { $0.id == key }
        )
        return try context.fetch(descriptor).first
    }

    /// Inserts a rate only when the cache key is absent — never overwrites or deletes.
    @discardableResult
    func insertIfAbsent(
        base: String,
        quote: String,
        rate: Decimal,
        rateDate: Date
    ) throws -> ExchangeRateCache {
        let normalizedDate = rateDate.utcStartOfDay
        if let existing = try cachedRate(base: base, quote: quote, on: normalizedDate) {
            return existing
        }
        let entry = ExchangeRateCache(
            baseCurrency: base,
            quoteCurrency: quote,
            rate: rate,
            rateDate: normalizedDate
        )
        context.insert(entry)
        try context.save()
        return entry
    }

    func hasEURRates(for currencies: Set<String>, on date: Date) throws -> Bool {
        let normalized = date.utcStartOfDay
        for code in currencies where code != "EUR" {
            if try cachedRate(base: "EUR", quote: code, on: normalized) == nil {
                return false
            }
        }
        return true
    }
}
