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

@Suite("CurrencyService — rate validation", .serialized)
struct CurrencyRateValidationTests {

    /// A provider decode glitch can yield Decimal.zero (Decimal(safeString:) falls back to
    /// .zero). Caching it would poison every cross-rate for the rest of the UTC day, because
    /// insertIfAbsent never overwrites. Zero must be rejected at the cache boundary.
    @Test("zero rate from a provider is not cached and does not poison the day")
    @MainActor
    func zeroRateRejected() async throws {
        let container = try CurrencyTestHarness.makeContainer()
        let primary = StubRateFetcher(label: "primary", result: .success(["USD": 0]))
        let fallback = StubRateFetcher(label: "fallback", result: .success(["USD": 0]))
        let service = CurrencyTestHarness.makeService(
            container: container,
            primary: primary,
            fallback: fallback
        )

        await #expect(throws: CurrencyError.self) {
            _ = try await service.rate(from: "USD", to: "EUR", on: Date.utcToday)
        }

        // The poisoned value must not be cached — a later fetch can still heal the day.
        let repo = ExchangeRateCacheRepository(context: container.mainContext)
        #expect(try repo.cachedRate(base: "EUR", quote: "USD", on: Date.utcToday) == nil)
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

@Suite("CurrencyService — re-home on currency switch", .serialized)
struct CurrencyRehomeTests {

    private static let eurUSD = Decimal(string: "1.1643", locale: Locale(identifier: "en_US_POSIX"))!

    // B5: switching home currency must convert existing history at the historical
    // rate, not re-label $10 as €10 at face value.
    @Test("re-home converts a home-currency expense at the historical rate")
    @MainActor
    func rehomeConvertsExpenseAtHistoricalRate() async throws {
        let container = try CurrencyTestHarness.makeContainer()
        let context = container.mainContext

        // $10.00 logged while home was USD — stored verbatim, rate 1.
        let expense = Expense(
            amountMinor: 1000,
            currencyCode: "USD",
            exchangeRateToHome: 1,
            homeCurrencyAtEntry: "USD",
            date: Date()
        )
        context.insert(expense)
        try context.save()

        let primary = StubRateFetcher(label: "primary", result: .success(["USD": Self.eurUSD]))
        let fallback = StubRateFetcher(label: "fallback", result: .success([:]))
        let service = CurrencyTestHarness.makeService(
            container: container, primary: primary, fallback: fallback
        )

        try await service.rehomeStoredData(from: "USD", to: "EUR")

        let usdToEUR = Decimal(1) / Self.eurUSD
        #expect(expense.homeCurrencyAtEntry == "EUR")
        #expect(expense.needsRateRefresh == false)
        #expect(expense.exchangeRateToHome == usdToEUR)

        // The total now reads in EUR, converted — not $10 mislabeled as €10.
        let expected = Money(minorUnits: 1000, currencyCode: "USD")
            .converted(to: "EUR", rate: usdToEUR).minorUnits
        #expect([expense].totalInHomeCurrency("EUR") == expected)
        #expect(expected != 1000)   // guards against the face-value bug
    }

    // An expense already in the new home currency short-circuits to rate 1 — no
    // network round-trip needed for that row.
    @Test("re-home leaves an expense already in the new home at rate 1")
    @MainActor
    func rehomeShortCircuitsNewHomeCurrency() async throws {
        let container = try CurrencyTestHarness.makeContainer()
        let context = container.mainContext

        // €25.00 logged while home was USD (foreign at the time).
        let expense = Expense(
            amountMinor: 2500,
            currencyCode: "EUR",
            exchangeRateToHome: Self.eurUSD,
            homeCurrencyAtEntry: "USD",
            date: Date()
        )
        context.insert(expense)
        try context.save()

        let primary = StubRateFetcher(label: "primary", result: .success([:]))
        let fallback = StubRateFetcher(label: "fallback", result: .success([:]))
        let service = CurrencyTestHarness.makeService(
            container: container, primary: primary, fallback: fallback
        )

        try await service.rehomeStoredData(from: "USD", to: "EUR")

        #expect(expense.homeCurrencyAtEntry == "EUR")
        #expect(expense.exchangeRateToHome == 1)
        #expect(expense.needsRateRefresh == false)
        #expect([expense].totalInHomeCurrency("EUR") == 2500)
    }

    // Category budgets are denominated in home currency too — convert at today's rate.
    @Test("re-home converts category budgets at today's rate")
    @MainActor
    func rehomeConvertsBudgets() async throws {
        let container = try CurrencyTestHarness.makeContainer()
        let context = container.mainContext

        let category = Category(
            name: "Groceries", iconName: "cart.fill", colorHex: "#45B7D1",
            monthlyBudgetMinor: 50000   // $500.00
        )
        context.insert(category)
        try context.save()

        let primary = StubRateFetcher(label: "primary", result: .success(["USD": Self.eurUSD]))
        let fallback = StubRateFetcher(label: "fallback", result: .success([:]))
        let service = CurrencyTestHarness.makeService(
            container: container, primary: primary, fallback: fallback
        )

        try await service.rehomeStoredData(from: "USD", to: "EUR")

        let usdToEUR = Decimal(1) / Self.eurUSD
        let expected = Money(minorUnits: 50000, currencyCode: "USD")
            .converted(to: "EUR", rate: usdToEUR).minorUnits
        #expect(category.monthlyBudgetMinor == expected)
        #expect(expected != 50000)
    }

    // Tapping the already-selected currency must not rewrite anything.
    @Test("re-home is a no-op when from == to")
    @MainActor
    func rehomeNoOpWhenUnchanged() async throws {
        let container = try CurrencyTestHarness.makeContainer()
        let context = container.mainContext
        let expense = Expense(
            amountMinor: 1000, currencyCode: "USD",
            exchangeRateToHome: 1, homeCurrencyAtEntry: "USD", date: Date()
        )
        context.insert(expense)
        try context.save()

        let primary = StubRateFetcher(label: "primary", result: .failure(CurrencyError.decodingFailed))
        let fallback = StubRateFetcher(label: "fallback", result: .failure(CurrencyError.decodingFailed))
        let service = CurrencyTestHarness.makeService(
            container: container, primary: primary, fallback: fallback
        )

        try await service.rehomeStoredData(from: "USD", to: "USD")

        #expect(expense.homeCurrencyAtEntry == "USD")
        #expect(expense.exchangeRateToHome == 1)
        #expect(expense.needsRateRefresh == false)
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

    @Test("batch 404 falls back to per-code fetch, returning the supported rates")
    func batch404PerCodeFallback() async throws {
        MockURLProtocol.reset()
        // Frankfurter 404s the entire batch when any one code is unsupported,
        // and 404s a lone unsupported code too. Mimic that: any request whose
        // `to` includes the unsupported code (IDR) fails; others succeed.
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            let to = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "to" })?.value ?? ""
            if to.contains("IDR") {
                let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (resp, Data())
            }
            let body = "{\"base\":\"EUR\",\"date\":\"2024-01-15\",\"rates\":{\"\(to)\":1.25}}"
            let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(body.utf8))
        }

        let client = FrankfurterClient(
            http: URLSessionHTTPClient(session: MockURLSessionFactory.make())
        )
        let rates = try await client.fetchRates(base: "EUR", quotes: ["USD", "IDR"], on: Date.utcToday)

        #expect(rates["USD"] == Decimal(string: "1.25", locale: Locale(identifier: "en_US_POSIX"))!)
        #expect(rates["IDR"] == nil)
    }

    @Test("batch 404 where every code is unsupported still throws")
    func batch404AllUnsupportedThrows() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        let client = FrankfurterClient(
            http: URLSessionHTTPClient(session: MockURLSessionFactory.make())
        )
        await #expect(throws: CurrencyError.self) {
            _ = try await client.fetchRates(base: "EUR", quotes: ["XXX", "YYY"], on: Date.utcToday)
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
