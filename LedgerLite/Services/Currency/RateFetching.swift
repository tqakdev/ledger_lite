import Foundation

/// Protocol seam between `CurrencyService` and rate API clients.
/// Tests inject fakes without hitting the network.
protocol RateFetching: Sendable {
    /// Fetches exchange rates with `base` as the pivot currency.
    /// Returns a map of quote currency code → rate (1 base = rate quote).
    func fetchRates(base: String, quotes: [String], on date: Date) async throws -> [String: Decimal]
}
