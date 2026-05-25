import Foundation

/// Fallback rate provider for currencies Frankfurter does not cover.
/// Uses the exchangerate.host API shape (`base` + `symbols` query params).
/// https://api.exchangerate.host/latest?base=EUR&symbols=USD,GBP
struct ExchangeRateHostClient: RateFetching {
    private let http: HTTPFetching
    private let baseURL: URL

    init(http: HTTPFetching = URLSessionHTTPClient(), baseURL: URL = Constants.URLs.exchangeRateHostBase) {
        self.http = http
        self.baseURL = baseURL
    }

    func fetchRates(base: String, quotes: [String], on date: Date) async throws -> [String: Decimal] {
        let filtered = quotes.filter { $0 != base }
        guard !filtered.isEmpty else { return [:] }

        let request = try buildRequest(base: base, quotes: filtered, on: date)
        let (data, response) = try await http.data(for: request)

        switch response.statusCode {
        case 200:
            let decoded = try decodeResponse(data: data, expectedBase: base)
            AppLogger.currency.info("ExchangeRateHost OK \(base)→[\(filtered.joined(separator: ","))] \(decoded.date)")
            return decoded.rates
        case 404:
            AppLogger.currency.error("ExchangeRateHost 404 for \(base)→[\(filtered.joined(separator: ","))]")
            throw CurrencyError.unsupportedCurrency(filtered.joined(separator: ","))
        default:
            AppLogger.currency.error("ExchangeRateHost HTTP \(response.statusCode)")
            if response.statusCode >= 500 {
                throw CurrencyError.networkUnavailable
            }
            throw CurrencyError.decodingFailed
        }
    }

    // MARK: - Private

    private func buildRequest(base: String, quotes: [String], on date: Date) throws -> URLRequest {
        let normalized = date.utcStartOfDay
        let dateString = ExchangeRateCache.dateString(for: normalized)
        let isToday = dateString == ExchangeRateCache.dateString(for: Date.utcToday)
        let path = isToday ? "latest" : dateString

        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "base", value: base),
            URLQueryItem(name: "symbols", value: quotes.joined(separator: ",")),
        ]
        guard let url = components.url else { throw CurrencyError.decodingFailed }
        return URLRequest(url: url)
    }

    private func decodeResponse(data: Data, expectedBase: String) throws -> (date: String, rates: [String: Decimal]) {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dict = json as? [String: Any] else { throw CurrencyError.decodingFailed }

        if let success = dict["success"] as? Bool, !success {
            if let errorInfo = dict["error"] as? [String: Any],
               let info = errorInfo["info"] as? String {
                AppLogger.currency.error("ExchangeRateHost API error: \(info)")
            }
            throw CurrencyError.decodingFailed
        }

        let decoded = try APIRateDecoder.decodeRates(from: data)
        guard decoded.base == expectedBase else { throw CurrencyError.decodingFailed }
        return (decoded.date, decoded.rates)
    }
}
