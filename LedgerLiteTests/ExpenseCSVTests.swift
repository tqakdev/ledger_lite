import Testing
import Foundation
@testable import LedgerLite

// MARK: - Helpers

private func makeExpense(
    amountMinor: Int = 1234,
    currencyCode: String = "USD",
    rate: Decimal = 1,
    homeCurrency: String = "USD",
    date: Date = Date(timeIntervalSince1970: 1_750_000_000),
    note: String? = nil,
    merchant: String? = "Blue Bottle"
) -> Expense {
    Expense(
        amountMinor: amountMinor,
        currencyCode: currencyCode,
        exchangeRateToHome: rate,
        homeCurrencyAtEntry: homeCurrency,
        date: date,
        note: note,
        merchant: merchant
    )
}

// MARK: - Field parsing

@Suite("ExpenseCSV — field parsing")
struct ExpenseCSVFieldTests {

    @Test("quoted commas and escaped quotes survive a round-trip")
    func quotingRoundTrip() {
        let line = [
            ExpenseCSV.escape("a,b"),
            ExpenseCSV.escape("say \"hi\""),
            ExpenseCSV.escape("plain"),
        ].joined(separator: ",")
        #expect(ExpenseCSV.parseFields(line) == ["a,b", "say \"hi\"", "plain"])
    }
}

// MARK: - Notes

@Suite("ExpenseCSV — note column")
struct ExpenseCSVNoteTests {

    /// "Your data is yours" — the backup must not silently drop the note field.
    @Test("export line carries the note and import restores it")
    @MainActor
    func noteRoundTrip() throws {
        let expense = makeExpense(note: "team lunch, split with Anna")
        let line = ExpenseCSV.line(for: expense)

        let row = try #require(ExpenseCSV.importedExpense(fromLine: line))
        #expect(row.note == "team lunch, split with Anna")
    }

    /// Scanned receipts produce multi-line notes; the file stays one-row-per-expense,
    /// so newlines must be escaped reversibly rather than truncated or leaked.
    @Test("multi-line note survives the round-trip on a single CSV line")
    @MainActor
    func multilineNoteRoundTrip() throws {
        let note = "Air Jordan 4 — $489.00\nCrew socks — $28.00"
        let line = ExpenseCSV.line(for: makeExpense(note: note))
        #expect(!line.contains("\n"), "an expense must serialize to exactly one line")

        let row = try #require(ExpenseCSV.importedExpense(fromLine: line))
        #expect(row.note == note)
    }

    @Test("legacy 7-field rows (pre-note exports) still import, with nil note")
    @MainActor
    func legacyRowsStillImport() throws {
        let legacy = "\"2026-06-01\",\"Uber\",\"Transport\",14.20,USD,14.20,USD"
        let row = try #require(ExpenseCSV.importedExpense(fromLine: legacy))
        #expect(row.note == nil)
        #expect(row.amountMinor == 1420)
    }
}

// MARK: - Dates

@Suite("ExpenseCSV — calendar-day fidelity")
struct ExpenseCSVDateTests {

    /// An expense logged at 8 PM in New York must export as that New York calendar day —
    /// the old UTC formatter wrote the *next* day for every evening expense.
    @Test("export writes the local calendar day, not the UTC day")
    @MainActor
    func exportUsesLocalCalendarDay() throws {
        let newYork = TimeZone(identifier: "America/New_York")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = newYork
        let eveningInNY = cal.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 20))!

        #expect(ExpenseCSV.dateString(for: eveningInNY, timeZone: newYork) == "2026-06-11")
    }

    @Test("import pins the row to local midnight of the written day")
    @MainActor
    func importUsesLocalMidnight() throws {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let date = try #require(ExpenseCSV.date(from: "2026-06-11", timeZone: tokyo))

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tokyo
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: date)
        #expect(comps.year == 2026 && comps.month == 6 && comps.day == 11)
        #expect(comps.hour == 0)
    }

    @Test("export and import round-trip preserves the calendar day in the same zone")
    @MainActor
    func roundTripPreservesDay() throws {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let lateEvening = cal.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 23, minute: 45))!

        let written = ExpenseCSV.dateString(for: lateEvening, timeZone: zone)
        let restored = try #require(ExpenseCSV.date(from: written, timeZone: zone))
        #expect(cal.isDate(restored, inSameDayAs: lateEvening))
    }
}
