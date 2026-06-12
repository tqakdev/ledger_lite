import Foundation

/// Pure CSV encode/decode for the Settings backup feature.
/// No SwiftData, no UI — extracted from SettingsView so the format is unit-testable.
enum ExpenseCSV {

    // The trailing ID column makes restore-from-backup idempotent (see `deduplicate`).
    // It stays last so older, id-less exports still parse and third-party CSVs that
    // omit it import unchanged.
    static let expenseHeader = "Date,Merchant,Category,Amount,Currency,HomeAmount,HomeCurrency,Note,ID"
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
        let note       = escape(escapeNewlines(e.note ?? ""))
        let id         = escape(e.id.uuidString)
        return "\(date),\(merchant),\(category),\(amount),\(e.currencyCode),\(homeAmount),\(e.homeCurrencyAtEntry),\(note),\(id)"
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
        let note: String?
        /// The originating expense's id when the row came from a LedgerLite export.
        /// `nil` for legacy (pre-ID) exports and third-party CSVs — those rows are
        /// always imported, never deduplicated.
        let id: UUID?
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

        // Column 8 (Note) was added later — legacy 7-field exports import with a nil note.
        let note: String? = fields.count >= 8 && !fields[7].isEmpty
            ? unescapeNewlines(fields[7])
            : nil

        // Column 9 (ID) is newer still. A missing or unparseable id reads as nil,
        // so the row is treated as brand new rather than rejected.
        let id: UUID? = fields.count >= 9 ? UUID(uuidString: fields[8]) : nil

        return ImportedExpense(
            date: date,
            merchant: fields[1].isEmpty ? nil : fields[1],
            categoryName: fields[2],
            amountMinor: amtMinor,
            currencyCode: currency,
            exchangeRateToHome: rate,
            homeCurrency: homeCurr,
            note: note,
            id: id
        )
    }

    /// Filters imported rows down to the ones that should actually be inserted,
    /// making restore-from-backup idempotent. A row is skipped when its id already
    /// exists in the store (`existingIDs`) or was already seen earlier in the same
    /// file. Rows without an id (legacy/third-party CSVs) are always kept — there's
    /// no identity to dedup on, and dropping them would lose data.
    static func deduplicate(
        _ rows: [ImportedExpense],
        existingIDs: Set<UUID>
    ) -> (unique: [ImportedExpense], skipped: Int) {
        var seen = existingIDs
        var unique: [ImportedExpense] = []
        var skipped = 0
        for row in rows {
            if let id = row.id {
                guard seen.insert(id).inserted else { skipped += 1; continue }
            }
            unique.append(row)
        }
        return (unique, skipped)
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

    /// Notes can be multi-line (scanned receipts list their line items), but the file
    /// format is one row per expense. Newlines are escaped reversibly: backslash first
    /// so the two transforms can't collide, then newline → literal "\n".
    static func escapeNewlines(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    static func unescapeNewlines(_ s: String) -> String {
        // Manual scan instead of chained replace — "\\\\n" must restore to "\\n",
        // not become a newline.
        var result = ""
        var iterator = s.makeIterator()
        while let ch = iterator.next() {
            guard ch == "\\" else { result.append(ch); continue }
            switch iterator.next() {
            case "n":          result.append("\n")
            case "\\":         result.append("\\")
            case let other?:   result.append("\\"); result.append(other)
            case nil:          result.append("\\")
            }
        }
        return result
    }

    // MARK: - Dates

    /// Writes the expense's *local* calendar day. The previous UTC formatter shifted
    /// every evening expense to the next day for users west of UTC.
    static func dateString(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    /// Parses a yyyy-MM-dd day to that day's local midnight, so the imported expense
    /// lands on the calendar day the file names.
    static func date(from string: String, timeZone: TimeZone = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        return formatter.date(from: string)
    }

    // MARK: - Private

    private static func toMinor(_ d: Decimal, places: Int) -> Int {
        let v = (d * Decimal.powerOfTen(places)).rounded(scale: 0)
        return NSDecimalNumber(decimal: v).intValue
    }
}
