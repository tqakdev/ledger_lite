import Testing
import Foundation
@testable import LedgerLite

// MARK: - Harness

private enum RunwayHarness {
    /// Fixed, timezone-stable calendar so day math is deterministic across machines.
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// 2026-06-01 00:00 UTC — fixed "today" for every test.
    static let today = Date(timeIntervalSince1970: 1_780_272_000)

    static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }
}

// MARK: - Tests

@Suite("RunwayForecast — projection engine")
struct RunwayForecastTests {

    /// With no bills and no discretionary spend, safe-per-day is simply balance ÷ days.
    @Test("safe-per-day is balance divided by days to payday when nothing is committed")
    func evenSplitNoBills() {
        let input = RunwayForecast.Input(
            startingBalanceMinor: 30_000,           // $300
            today: RunwayHarness.today,
            payday: RunwayHarness.day(10),          // 10 days out
            bills: [],
            projectedDailyDiscretionaryMinor: 0,
            calendar: RunwayHarness.calendar
        )
        let r = RunwayForecast.project(input)

        #expect(r.daysToPayday == 10)
        #expect(r.trulySafePerDayMinor == 3_000)    // $300 / 10 = $30/day
        #expect(r.totalUpcomingBillsMinor == 0)
        #expect(r.firstNegativeDate == nil)
    }

    /// Committed bills before payday must reduce the truly-safe figure.
    @Test("upcoming bills are netted out of safe-to-spend")
    func billsReduceSafeToSpend() {
        let input = RunwayForecast.Input(
            startingBalanceMinor: 60_000,           // $600
            today: RunwayHarness.today,
            payday: RunwayHarness.day(12),          // 12 days
            bills: [
                .init(date: RunwayHarness.day(3),  amountMinor: 20_000, name: "Rent share"),
                .init(date: RunwayHarness.day(7),  amountMinor: 14_000, name: "Bundle"),
            ],
            projectedDailyDiscretionaryMinor: 0,
            calendar: RunwayHarness.calendar
        )
        let r = RunwayForecast.project(input)

        // ($600 - $340) / 12 = $21.66 → 2166 minor units (integer division)
        #expect(r.totalUpcomingBillsMinor == 34_000)
        #expect(r.trulySafePerDayMinor == (60_000 - 34_000) / 12)
        #expect(r.upcomingBills.count == 2)
    }

    /// Bills dated after payday (or today) are outside the window and ignored.
    @Test("bills outside the (today, payday] window are excluded")
    func billsOutsideWindowIgnored() {
        let input = RunwayForecast.Input(
            startingBalanceMinor: 50_000,
            today: RunwayHarness.today,
            payday: RunwayHarness.day(5),
            bills: [
                .init(date: RunwayHarness.today,    amountMinor: 9_999, name: "Today (excluded)"),
                .init(date: RunwayHarness.day(5),   amountMinor: 5_000, name: "On payday (included)"),
                .init(date: RunwayHarness.day(40),  amountMinor: 8_000, name: "After payday (excluded)"),
            ],
            projectedDailyDiscretionaryMinor: 0,
            calendar: RunwayHarness.calendar
        )
        let r = RunwayForecast.project(input)

        #expect(r.totalUpcomingBillsMinor == 5_000)
        #expect(r.upcomingBills.count == 1)
        #expect(r.upcomingBills.first?.name == "On payday (included)")
    }

    /// The descriptive curve must flag the first day the balance dips negative.
    @Test("curve detects the first negative day at the current spend rate")
    func detectsFirstNegativeDay() {
        // $100 balance, spending $30/day with no bills → negative on day 4
        // day0 100, day1 70, day2 40, day3 10, day4 -20
        let input = RunwayForecast.Input(
            startingBalanceMinor: 10_000,
            today: RunwayHarness.today,
            payday: RunwayHarness.day(7),
            bills: [],
            projectedDailyDiscretionaryMinor: 3_000,
            calendar: RunwayHarness.calendar
        )
        let r = RunwayForecast.project(input)

        #expect(r.firstNegativeDate == RunwayHarness.day(4))
        #expect(r.lowestBalanceMinor < 0)
        #expect(r.dailyBalances.count == 8)   // today through payday inclusive
    }

    /// When committed bills already exceed the balance, safe-to-spend floors at zero
    /// rather than going negative.
    @Test("safe-to-spend never goes below zero")
    func safeToSpendFloorsAtZero() {
        let input = RunwayForecast.Input(
            startingBalanceMinor: 10_000,
            today: RunwayHarness.today,
            payday: RunwayHarness.day(8),
            bills: [.init(date: RunwayHarness.day(2), amountMinor: 25_000, name: "Big bill")],
            projectedDailyDiscretionaryMinor: 0,
            calendar: RunwayHarness.calendar
        )
        let r = RunwayForecast.project(input)

        #expect(r.trulySafePerDayMinor == 0)
        #expect(r.firstNegativeDate == RunwayHarness.day(2))
    }

    /// A payday on/before today collapses to a single-day horizon (never divides by zero).
    @Test("non-future payday clamps days-to-payday to 1")
    func paydayInPastClampsToOneDay() {
        let input = RunwayForecast.Input(
            startingBalanceMinor: 5_000,
            today: RunwayHarness.today,
            payday: RunwayHarness.day(-3),
            bills: [],
            projectedDailyDiscretionaryMinor: 0,
            calendar: RunwayHarness.calendar
        )
        let r = RunwayForecast.project(input)

        #expect(r.daysToPayday == 1)
        #expect(r.trulySafePerDayMinor == 5_000)
    }
}
