import Foundation

enum CurrencyError: Error, Equatable {
    case networkUnavailable
    case unsupportedCurrency(String)
    case decodingFailed
    case rateNotFound(from: String, to: String, date: Date)
}
