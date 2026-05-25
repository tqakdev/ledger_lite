import Foundation

/// Primary rate provider — ECB-backed, free, no API key.
/// https://api.frankfurter.app/latest?from=EUR&to=USD,GBP
/// https://api.frankfurter.app/2024-01-15?from=EUR&to=USD
struct FrankfurterClient: RateFetching {
    private let http: HTTPFetching
    private let baseURL: URL

    init(http: HTTPFetching = URLSessionHTTPClient(), baseURL: URL = Constants.URLs.frankfurterBase) {
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
            let decoded = try APIRateDecoder.decodeRates(from: data)
            guard decoded.base == base else { throw CurrencyError.decodingFailed }
            AppLogger.currency.info("Frankfurter OK \(base)→[\(filtered.joined(separator: ","))] \(decoded.date)")
            return decoded.rates
        case 404:
            AppLogger.currency.error("Frankfurter 404 for \(base)→[\(filtered.joined(separator: ","))]")
            throw CurrencyError.unsupportedCurrency(filtered.joined(separator: ","))
        default:
            AppLogger.currency.error("Frankfurter HTTP \(response.statusCode) for \(request.url?.absoluteString ?? "?")")
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
            URLQueryItem(name: "from", value: base),
            URLQueryItem(name: "to", value: quotes.joined(separator: ",")),
        ]
        guard let url = components.url else { throw CurrencyError.decodingFailed }
        return URLRequest(url: url)
    }
}

extension Error {
    var isNetworkUnavailable: Bool {
        if let currency = self as? CurrencyError, currency == .networkUnavailable { return true }
        if let urlError = self as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .timedOut:
                return true
            default:
                return false
            }
        }
        return false
    }
}
