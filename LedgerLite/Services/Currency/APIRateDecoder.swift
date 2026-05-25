import Foundation

/// Shared JSON helpers for ECB-style rate API responses.
enum APIRateDecoder {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func decodeRates(from data: Data) throws -> (base: String, date: String, rates: [String: Decimal]) {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dict = json as? [String: Any] else { throw CurrencyError.decodingFailed }

        guard let base = dict["base"] as? String, !base.isEmpty else {
            throw CurrencyError.decodingFailed
        }

        let date = (dict["date"] as? String) ?? ExchangeRateCache.dateString(for: Date())

        guard let ratesObject = dict["rates"] as? [String: Any] else {
            throw CurrencyError.decodingFailed
        }

        var rates: [String: Decimal] = [:]
        rates.reserveCapacity(ratesObject.count)
        for (code, value) in ratesObject {
            rates[code] = decimal(from: value)
        }
        return (base, date, rates)
    }

    private static func decimal(from value: Any) -> Decimal {
        switch value {
        case let string as String:
            return Decimal(safeString: string)
        case let int as Int:
            return Decimal(int)
        case let double as Double:
            return Decimal(string: String(double), locale: posix) ?? .zero
        case let number as NSNumber:
            return Decimal(string: number.stringValue, locale: posix) ?? .zero
        default:
            return .zero
        }
    }
}
