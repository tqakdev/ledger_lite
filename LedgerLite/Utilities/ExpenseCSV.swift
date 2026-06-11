import Foundation

/// Pure CSV encode/decode for the Settings backup feature.
/// No SwiftData, no UI — extracted from SettingsView so the format is unit-testable.
enum ExpenseCSV {

    static let expenseHeader = "Date,Merchant,Category,Amount,Currency,HomeAmount,HomeCurrency"
    static let subscriptionHeader = "Name,Amount,Currency,BillingCycle,NextBillingDate,Status"

    // MARK: - Export

    static func line(for e: Expense) -> String {
        let date       = escape(dateString(for: e.date))
        let merchant   = escape(e.merchant ?? "")
        let category   = escape(e.category?.name ?? "")
        let amount     = e.money.decimalValue.description
        let homeAmount = (e.money.decimalValue * e.exchangeRateToHome)
            .rounded(scale: Money.decimals(for: e.homeCurrencyAtEntry))
            .description
        return "\(date),\(merchant),\(category),\(amount),\(e.currencyCode),\(homeAmount),\(e.homeCurrencyAtEntry)"
    }

    static func line(for s: Subscription) -> String {
        let name     = escape(s.name)
        let amount   = s.money.decimalValue.description
        let cycle    = escape(s.billingCycle.rawValue)
        let nextDate = escape(dateString(for: s.nextBillingDate))
        let status   = escape(s.status.rawValue)
        return "\(name),\(amount),\(s.currencyCode),\(cycle),\(nextDate),\(status)"
    }

    // MARK: - Import

    /// A validated expense row, ready to be turned into an `Expense`.
    struct ImportedExpense: Equatable {
        let date: Date
        let merchant: String?
        let categoryName: String
        let amountMinor: Int
        let currencyCode: String
        let exchangeRateToHome: Decimal
        let homeCurrency: String
    }

    /// Parses one data line. Returns nil for malformed rows (wrong field count,
    /// unparseable date, non-positive amount) — callers skip those.
    static func importedExpense(fromLine line: String) -> ImportedExpense? {
        let fields = parseFields(line)
        guard fields.count >= 7 else { return nil }

        guard let date = date(from: fields[0]) else { return nil }
        guard let amtDecimal = Decimal(string: fields[3]), amtDecimal > 0 else { return nil }
        guard let homeDecimal = Decimal(string: fields[5]) else { return nil }

        let currency = fields[4]
        let homeCurr = fields[6]
        let amtMinor = toMinor(amtDecimal, places: Money.decimals(for: currency))
        guard amtMinor > 0 else { return nil }

        let rate: Decimal = (currency == homeCurr || amtDecimal == Decimal(0))
            ? Decimal(1) : (homeDecimal / amtDecimal)

        return ImportedExpense(
            date: date,
            merchant: fields[1].isEmpty ? nil : fields[1],
            categoryName: fields[2],
            amountMinor: amtMinor,
            currencyCode: currency,
            exchangeRateToHome: rate,
            homeCurrency: homeCurr
        )
    }

    /// Splits a CSV line into fields, honoring double-quote escaping.
    static func parseFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if ch == "\"" {
                let next = line.index(after: i)
                if inQuotes && next < line.endIndex && line[next] == "\"" {
                    current.append("\"")
                    i = line.index(after: next)
                    continue
                }
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            i = line.index(after: i)
        }
        fields.append(current)
        return fields
    }

    static func escape(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Dates

    static func dateString(for date: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        return iso.string(from: date)
    }

    static func date(from string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        return iso.date(from: string)
    }

    // MARK: - Private

    private static func toMinor(_ d: Decimal, places: Int) -> Int {
        let v = (d * Decimal.powerOfTen(places)).rounded(scale: 0)
        return NSDecimalNumber(decimal: v).intValue
    }
}
