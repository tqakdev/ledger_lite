import Foundation

/// Protocol seam for HTTP transport — tests inject `MockURLProtocol` via a custom `URLSession`.
protocol HTTPFetching: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPClient: HTTPFetching {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CurrencyError.decodingFailed
        }
        return (data, http)
    }
}
