import Foundation

/// Fallback rate provider using open.er-api.com (free, no API key, stable since 2019).
/// Endpoint: GET https://open.er-api.com/v6/latest/{base}
/// Note: free tier returns live rates only — historical-date requests fall back to latest available.
struct OpenERAPIClient: RateFetching {
    private let http: HTTPFetching
    private let baseURL: URL

    init(http: HTTPFetching = URLSessionHTTPClient(), baseURL: URL = Constants.URLs.openERAPIBase) {
        self.http = http
        self.baseURL = baseURL
    }

    func fetchRates(base: String, quotes: [String], on date: Date) async throws -> [String: Decimal] {
        let filtered = quotes.filter { $0 != base }
        guard !filtered.isEmpty else { return [:] }

        let (data, response) = try await http.data(for: buildRequest(base: base))

        switch response.statusCode {
        case 200:
            let all = try decodeRates(from: data, expectedBase: base)
            let result = all.filter { filtered.contains($0.key) }
            AppLogger.currency.info("OpenERAPI OK \(base)→[\(filtered.joined(separator: ","))]")
            return result
        case 404:
            AppLogger.currency.error("OpenERAPI 404 for base \(base)")
            throw CurrencyError.unsupportedCurrency(base)
        default:
            AppLogger.currency.error("OpenERAPI HTTP \(response.statusCode)")
            throw response.statusCode >= 500 ? CurrencyError.networkUnavailable : CurrencyError.decodingFailed
        }
    }

    // MARK: - Private

    private func buildRequest(base: String) -> URLRequest {
        let url = baseURL
            .appendingPathComponent("v6")
            .appendingPathComponent("latest")
            .appendingPathComponent(base)
        return URLRequest(url: url)
    }

    private func decodeRates(from data: Data, expectedBase: String) throws -> [String: Decimal] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CurrencyError.decodingFailed
        }
        guard (json["result"] as? String) == "success" else { throw CurrencyError.decodingFailed }
        guard (json["base_code"] as? String) == expectedBase else { throw CurrencyError.decodingFailed }
        guard let ratesDict = json["rates"] as? [String: Any] else { throw CurrencyError.decodingFailed }

        let posix = Locale(identifier: "en_US_POSIX")
        var rates: [String: Decimal] = [:]
        rates.reserveCapacity(ratesDict.count)
        for (code, value) in ratesDict {
            switch value {
            case let d as Double:
                rates[code] = Decimal(string: String(d), locale: posix) ?? .zero
            case let n as NSNumber:
                rates[code] = Decimal(string: n.stringValue, locale: posix) ?? .zero
            case let i as Int:
                rates[code] = Decimal(i)
            default:
                break
            }
        }
        return rates
    }
}
