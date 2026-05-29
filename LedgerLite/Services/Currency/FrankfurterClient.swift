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

        do {
            return try await fetchBatch(base: base, quotes: filtered, on: date)
        } catch CurrencyError.unsupportedCurrency where filtered.count > 1 {
            // Frankfurter 404s the *entire* batch when any one code is unsupported,
            // so a single bad currency would otherwise sink the rates for all the
            // good ones. Re-fetch each code on its own and keep what resolves.
            AppLogger.currency.error("Frankfurter batch 404 \(base)→[\(filtered.joined(separator: ","))]; retrying per code")
            return try await fetchPerCode(base: base, quotes: filtered, on: date)
        }
    }

    // MARK: - Private

    /// Fetches all `quotes` in a single request. Throws `unsupportedCurrency` on 404.
    private func fetchBatch(base: String, quotes: [String], on date: Date) async throws -> [String: Decimal] {
        let request = try buildRequest(base: base, quotes: quotes, on: date)
        let (data, response) = try await http.data(for: request)

        switch response.statusCode {
        case 200:
            let decoded = try APIRateDecoder.decodeRates(from: data)
            guard decoded.base == base else { throw CurrencyError.decodingFailed }
            AppLogger.currency.info("Frankfurter OK \(base)→[\(quotes.joined(separator: ","))] \(decoded.date)")
            return decoded.rates
        case 404:
            throw CurrencyError.unsupportedCurrency(quotes.joined(separator: ","))
        default:
            AppLogger.currency.error("Frankfurter HTTP \(response.statusCode) for \(request.url?.absoluteString ?? "?")")
            if response.statusCode >= 500 {
                throw CurrencyError.networkUnavailable
            }
            throw CurrencyError.decodingFailed
        }
    }

    /// Retries each quote individually, collecting the rates that resolve and
    /// dropping any that 404. Throws `unsupportedCurrency` only if none succeed.
    private func fetchPerCode(base: String, quotes: [String], on date: Date) async throws -> [String: Decimal] {
        var rates: [String: Decimal] = [:]
        var unsupported: [String] = []
        for quote in quotes {
            do {
                let single = try await fetchBatch(base: base, quotes: [quote], on: date)
                rates.merge(single) { _, new in new }
            } catch CurrencyError.unsupportedCurrency {
                unsupported.append(quote)
            }
        }
        guard !rates.isEmpty else {
            throw CurrencyError.unsupportedCurrency(quotes.joined(separator: ","))
        }
        if !unsupported.isEmpty {
            AppLogger.currency.error("Frankfurter unsupported: \(unsupported.joined(separator: ","))")
        }
        return rates
    }

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
