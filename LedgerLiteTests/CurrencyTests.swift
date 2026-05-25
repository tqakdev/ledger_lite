import Testing
import Foundation
import SwiftData
@testable import LedgerLite

// MARK: - Test harness

@MainActor
private enum CurrencyTestHarness {
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Expense.self,
            Subscription.self,
            Category.self,
            ExchangeRateCache.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func makeService(
        container: ModelContainer,
        primary: RateFetching,
        fallback: RateFetching
    ) -> CurrencyService {
        CurrencyService(
            context: container.mainContext,
            primary: primary,
            fallback: fallback
        )
    }
}

// MARK: - Stub fetchers

private final class StubRateFetcher: RateFetching, @unchecked Sendable {
    let label: String
    var result: Result<[String: Decimal], Error>
    private(set) var calls: [String] = []

    init(label: String, result: Result<[String: Decimal], Error>) {
        self.label = label
        self.result = result
    }

    func fetchRates(base: String, quotes: [String], on date: Date) async throws -> [String: Decimal] {
        calls.append(label)
        return try result.get()
    }
}

private struct FailingRateFetcher: RateFetching {
    let error: Error
    func fetchRates(base: String, quotes: [String], on date: Date) async throws -> [String: Decimal] {
        throw error
    }
}

// MARK: - CurrencyService

@Suite("CurrencyService — cross-rate via EUR", .serialized)
struct CurrencyCrossRateTests {

    @Test("USD→GBP = (EUR→GBP) / (EUR→USD)")
    @MainActor
    func crossRateMath() async throws {
        let container = try CurrencyTestHarness.makeContainer()
        let eurUSD = Decimal(string: "1.1643", locale: Locale(identifier: "en_US_POSIX"))!
        let eurGBP = Decimal(string: "0.86255", locale: Locale(identifier: "en_US_POSIX"))!

        let primary = StubRateFetcher(
            label: "primary",
            result: .success(["USD": eurUSD, "GBP": eurGBP])
        )
        let fallback = StubRateFetcher(label: "fallback", result: .success([:]))

        let service = CurrencyTestHarness.makeService(
            container: container,
            primary: primary,
            fallback: fallback
        )

        let rate = try await service.rate(from: "USD", to: "GBP", on: Date.utcToday)
        let expected = eurGBP / eurUSD
        #expect(rate == expected)
        #expect(primary.calls.allSatisfy { $0 == "primary" })
        #expect(!primary.calls.isEmpty)
    }
}

@Suite("CurrencyService — cache idempotency", .serialized)
struct CurrencyCacheTests {

    @Test("ensureTodayRates skips network when today's EUR rates exist")
    @MainActor
    func cacheHitSkipsNetwork() async throws {
        let container = try CurrencyTestHarness.makeContainer()
        let repo = ExchangeRateCacheRepository(context: container.mainContext)
        let today = Date.utcToday
        _ = try repo.insertIfAbsent(
            base: "EUR",
            quote: "USD",
            rate: Decimal(string: "1.1643", locale: Locale(identifier: "en_US_POSIX"))!,
            rateDate: today
        )
        #expect(try repo.hasEURRates(for: ["USD", "EUR"], on: today))

        let primary = StubRateFetcher(
            label: "primary",
            result: .failure(CurrencyError.decodingFailed)
        )
        let fallback = StubRateFetcher(label: "fallback", result: .failure(CurrencyError.decodingFailed))

        let service = CurrencyTestHarness.makeService(
            container: container,
            primary: primary,
            fallback: fallback
        )

        try await service.ensureTodayRates(for: ["USD"])
        #expect(primary.calls.isEmpty)
        #expect(fallback.calls.isEmpty)
    }
}

@Suite("CurrencyService — offline", .serialized)
struct CurrencyOfflineTests {

    @Test("no cache + network failure → networkUnavailable")
    @MainActor
    func offlineThrowsNetworkUnavailable() async throws {
        let container = try CurrencyTestHarness.makeContainer()
        let offline = FailingRateFetcher(error: URLError(.notConnectedToInternet))
        let service = CurrencyTestHarness.makeService(
            container: container,
            primary: offline,
            fallback: offline
        )

        await #expect(throws: CurrencyError.networkUnavailable) {
            _ = try await service.rate(from: "USD", to: "EUR", on: Date.utcToday)
        }
    }
}

@Suite("CurrencyService — fallback", .serialized)
struct CurrencyFallbackTests {

    @Test("primary 404-equivalent triggers fallback fetcher")
    @MainActor
    func fallbackOnPrimaryUnsupported() async throws {
        let container = try CurrencyTestHarness.makeContainer()

        let primary = StubRateFetcher(
            label: "primary",
            result: .failure(CurrencyError.unsupportedCurrency("IDR"))
        )
        let fallback = StubRateFetcher(
            label: "fallback",
            result: .success(["IDR": Decimal(20_524)])
        )

        let service = CurrencyTestHarness.makeService(
            container: container,
            primary: primary,
            fallback: fallback
        )

        let rate = try await service.rate(from: "IDR", to: "EUR", on: Date.utcToday)
        #expect(rate == Decimal(1) / Decimal(20_524))
        #expect(primary.calls == ["primary"])
        #expect(fallback.calls == ["fallback"])
    }
}

@Suite("CurrencyService — rehydrate stale rates", .serialized)
struct CurrencyRehydrateTests {

    @Test("rehydrateStaleRates clears needsRateRefresh and patches rate")
    @MainActor
    func rehydratePatchesExpenses() async throws {
        let container = try CurrencyTestHarness.makeContainer()
        let context = container.mainContext

        let expense = Expense(
            amountMinor: 1000,
            currencyCode: "USD",
            exchangeRateToHome: 1,
            homeCurrencyAtEntry: "EUR",
            needsRateRefresh: true
        )
        context.insert(expense)
        try context.save()

        let eurUSD = Decimal(string: "1.1643", locale: Locale(identifier: "en_US_POSIX"))!
        let primary = StubRateFetcher(label: "primary", result: .success(["USD": eurUSD]))
        let fallback = StubRateFetcher(label: "fallback", result: .success([:]))

        let service = CurrencyTestHarness.makeService(
            container: container,
            primary: primary,
            fallback: fallback
        )

        try await service.rehydrateStaleRates()
        #expect(expense.needsRateRefresh == false)
        #expect(expense.exchangeRateToHome == Decimal(1) / eurUSD)
    }
}

// MARK: - FrankfurterClient (HTTP mock)

@Suite("FrankfurterClient — HTTP", .serialized)
struct FrankfurterClientTests {

    @Test("decodes latest fixture and builds correct URL")
    func latestRequest() async throws {
        MockURLProtocol.reset()
        let fixture = try FixtureLoader.data(named: "frankfurter_latest")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, fixture)
        }

        let client = FrankfurterClient(
            http: URLSessionHTTPClient(session: MockURLSessionFactory.make())
        )
        let rates = try await client.fetchRates(
            base: "EUR",
            quotes: ["USD", "GBP"],
            on: Date.utcToday
        )

        #expect(rates["USD"] == Decimal(string: "1.1643", locale: Locale(identifier: "en_US_POSIX"))!)
        #expect(rates["GBP"] == Decimal(string: "0.86255", locale: Locale(identifier: "en_US_POSIX"))!)
        let url = try #require(MockURLProtocol.lastRequest?.url?.absoluteString)
        #expect(url.contains("/latest"))
        #expect(url.contains("from=EUR"))
        #expect(url.contains("to=USD"))
        #expect(MockURLProtocol.requestCount == 1)
    }

    @Test("historical date uses yyyy-MM-dd path")
    func historicalPath() async throws {
        MockURLProtocol.reset()
        let fixture = try FixtureLoader.data(named: "frankfurter_historical")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, fixture)
        }

        let client = FrankfurterClient(
            http: URLSessionHTTPClient(session: MockURLSessionFactory.make())
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let historical = calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!

        _ = try await client.fetchRates(base: "EUR", quotes: ["USD"], on: historical)
        let url = try #require(MockURLProtocol.lastRequest?.url?.absoluteString)
        #expect(url.contains("/2024-01-15"))
    }

    @Test("HTTP 404 → unsupportedCurrency")
    func notFound() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let client = FrankfurterClient(
            http: URLSessionHTTPClient(session: MockURLSessionFactory.make())
        )

        await #expect(throws: CurrencyError.unsupportedCurrency("IDR")) {
            _ = try await client.fetchRates(base: "EUR", quotes: ["IDR"], on: Date.utcToday)
        }
    }
}

// MARK: - Live integration (gated)

@Suite("Currency — live API", .enabled(if: ProcessInfo.processInfo.environment["LEDGERLITE_LIVE_TESTS"] == "1"))
struct CurrencyLiveTests {

    @Test("Frankfurter latest EUR→USD returns a positive rate")
    func liveFrankfurterLatest() async throws {
        let client = FrankfurterClient()
        let rates = try await client.fetchRates(base: "EUR", quotes: ["USD"], on: Date.utcToday)
        let usd = try #require(rates["USD"])
        #expect(usd > 0)
    }
}
