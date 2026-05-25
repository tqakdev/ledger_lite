import Foundation
import SwiftData

@Model
final class ExchangeRateCache {
    // No @Attribute(.unique) — CloudKit-compatible.
    // Uniqueness key: "\(baseCurrency)-\(quoteCurrency)-yyyy-MM-dd" — enforced in repository.
    var id: String = ""
    var baseCurrency: String = ""
    var quoteCurrency: String = ""
    var rate: Decimal = 0
    var rateDate: Date = Date()      // the rate's effective date, not the fetch time
    var fetchedAt: Date = Date()

    // MARK: Init

    init(
        baseCurrency: String,
        quoteCurrency: String,
        rate: Decimal,
        rateDate: Date,
        fetchedAt: Date = Date()
    ) {
        self.baseCurrency = baseCurrency
        self.quoteCurrency = quoteCurrency
        self.rate = rate
        self.rateDate = rateDate
        self.fetchedAt = fetchedAt
        self.id = Self.cacheKey(base: baseCurrency, quote: quoteCurrency, date: rateDate)
    }

    // MARK: Key helpers

    static func cacheKey(base: String, quote: String, date: Date) -> String {
        "\(base)-\(quote)-\(dateString(for: date))"
    }

    static func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
