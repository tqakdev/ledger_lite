import Foundation

/// Pure, deterministic projection of available balance from today until the next payday.
///
/// This is what separates Ledger Lite from a backward-looking ledger: instead of charting
/// money already spent, it answers "what can I actually spend today and still make it to
/// payday after the bills I've already committed to?"
///
/// The headline output, `trulySafePerDayMinor`, is prescriptive — spend that much each
/// remaining day and you cover every bill due before payday and arrive at payday at ≥ 0.
/// The `dailyBalances` curve is descriptive — it shows where the balance lands if spending
/// continues at the current discretionary rate, including the day it would dip negative.
///
/// No SwiftData and no Foundation singletons beyond an injected `Calendar` — fully testable.
struct RunwayForecast {

    /// A single committed outflow (typically a subscription billing) on a given day.
    struct Bill: Equatable {
        let date: Date          // day the bill is charged
        let amountMinor: Int    // home-currency minor units
        let name: String
    }

    struct Input {
        /// Effective available balance as of `today` (home-currency minor units).
        let startingBalanceMinor: Int
        let today: Date
        let payday: Date
        /// Upcoming bills. The engine keeps only those in the window (today, payday].
        let bills: [Bill]
        /// Expected non-bill ("discretionary") spend per day, from recent velocity.
        let projectedDailyDiscretionaryMinor: Int
        var calendar: Calendar = .current
    }

    struct DayPoint: Equatable {
        let date: Date
        let balanceMinor: Int
    }

    struct Result: Equatable {
        /// Projected balance for each day from today through payday (inclusive).
        let dailyBalances: [DayPoint]
        /// Prescriptive: spend this per day to cover all bills and land at payday ≥ 0.
        let trulySafePerDayMinor: Int
        /// The lowest point the projected curve reaches before payday.
        let lowestBalanceMinor: Int
        /// First day the projected balance goes below zero, if any.
        let firstNegativeDate: Date?
        /// Sum of all bills due in (today, payday].
        let totalUpcomingBillsMinor: Int
        /// Whole days from today to payday (never less than 1).
        let daysToPayday: Int
        /// Bills due in the window, sorted by date — surfaced to the UI as markers/list.
        let upcomingBills: [Bill]
    }

    static func project(_ input: Input) -> Result {
        let cal = input.calendar
        let today = cal.startOfDay(for: input.today)
        let payday = cal.startOfDay(for: input.payday)

        let rawDays = cal.dateComponents([.day], from: today, to: payday).day ?? 0
        let daysToPayday = max(1, rawDays)

        // Keep only bills strictly after today, up to and including payday.
        let upcoming = input.bills
            .filter { bill in
                let d = cal.startOfDay(for: bill.date)
                return d > today && d <= payday
            }
            .sorted { $0.date < $1.date }
        let totalBills = upcoming.reduce(0) { $0 + $1.amountMinor }

        // Headline: spend evenly, cover every committed bill, reach payday at ≥ 0.
        let safePerDay = max(0, (input.startingBalanceMinor - totalBills) / daysToPayday)

        // Descriptive curve: subtract bills on their day plus the projected daily spend.
        var balance = input.startingBalanceMinor
        var points: [DayPoint] = [DayPoint(date: today, balanceMinor: balance)]
        var lowest = balance
        var firstNegative: Date? = balance < 0 ? today : nil

        for offset in 1...daysToPayday {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { break }
            let dayBills = upcoming
                .filter { cal.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.amountMinor }
            balance -= dayBills
            balance -= input.projectedDailyDiscretionaryMinor
            points.append(DayPoint(date: day, balanceMinor: balance))
            if balance < lowest { lowest = balance }
            if firstNegative == nil, balance < 0 { firstNegative = day }
        }

        return Result(
            dailyBalances: points,
            trulySafePerDayMinor: safePerDay,
            lowestBalanceMinor: lowest,
            firstNegativeDate: firstNegative,
            totalUpcomingBillsMinor: totalBills,
            daysToPayday: daysToPayday,
            upcomingBills: upcoming
        )
    }
}
