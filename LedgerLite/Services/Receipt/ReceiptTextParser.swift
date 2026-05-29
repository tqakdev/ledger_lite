import Foundation

/// Stateless heuristics that turn a receipt's OCR text into a `ParsedReceipt`.
/// No Vision, no SwiftData, no SwiftUI — pure and fully unit-testable, mirroring
/// `SubscriptionDetector`. The OCR step lives in `ReceiptScanner`; keeping it out
/// of here means all the real logic is covered without needing real images.
enum ReceiptTextParser {

    // Most-specific prefix first so "$" (USD) doesn't shadow "A$" (AUD).
    private static let symbolMap: [(symbol: String, code: String)] = [
        ("HK$", "HKD"), ("NZ$", "NZD"), ("A$", "AUD"), ("C$", "CAD"), ("S$", "SGD"),
        ("R$", "BRL"), ("₹", "INR"), ("€", "EUR"), ("£", "GBP"), ("¥", "JPY"),
        ("₩", "KRW"), ("₺", "TRY"), ("฿", "THB"), ("$", "USD"),
    ]

    // Strongest first — a "grand total" beats a bare "total" beats "amount".
    private static let totalKeywordTiers: [[String]] = [
        ["grand total", "total due", "amount due", "balance due", "total to pay", "amount to pay"],
        ["total", "balance", "to pay"],
        ["amount"],
    ]

    // Lines whose total-like number must be ignored — they are not the bill total.
    private static let totalExclusions: [String] = [
        "subtotal", "sub total", "tax", "vat", "gst", "tip", "gratuity",
        "change", "cash", "tendered", "savings", "discount", "points",
    ]

    // Words that never make a good merchant guess. Note: "store"/"shop" are
    // deliberately NOT here — they appear in real names ("Nike Store", "Body Shop").
    private static let merchantNoise: Set<String> = [
        "receipt", "invoice", "order #", "cashier", "welcome", "thank you",
        "thanks", "tel:", "phone", "fax", "date", "time",
    ]

    // MARK: - Public

    static func parse(_ text: String, defaultCurrency: String? = nil) -> ParsedReceipt {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let currency = detectCurrency(in: text) ?? defaultCurrency
        let decimals = Money.decimals(for: currency ?? "USD")
        let (amount, confident) = detectTotal(lines: lines, decimals: decimals)

        return ParsedReceipt(
            amountMinor: amount,
            currencyCode: currency,
            merchant: detectMerchant(lines: lines),
            date: detectDate(in: text),
            amountConfident: confident,
            lineItems: detectLineItems(lines: lines, decimals: decimals),
            rawText: text
        )
    }

    // MARK: - Currency

    private static func detectCurrency(in text: String) -> String? {
        for entry in symbolMap where text.contains(entry.symbol) {
            return entry.code
        }
        // ISO code appearing as a standalone token, e.g. "EUR 12.00".
        let upper = text.uppercased()
        for code in Constants.App.supportedCurrencies where upper.contains(code) {
            return code
        }
        return nil
    }

    // MARK: - Total

    /// Returns the total in minor units and whether it came from an explicit label.
    /// Vision often splits a "Total" label and its amount onto separate lines in
    /// either order, so the amount is looked for on the same line and both neighbours.
    private static func detectTotal(lines: [String], decimals: Int) -> (Int?, Bool) {
        for tier in totalKeywordTiers {
            var best: Decimal?
            for (index, line) in lines.enumerated() {
                let lower = line.lowercased()
                guard tier.contains(where: { lower.contains($0) }) else { continue }
                guard !totalExclusions.contains(where: { lower.contains($0) }) else { continue }

                var amount = lastMoney(in: line, decimals: decimals)?.value
                if amount == nil {
                    for neighbour in [index + 1, index - 1] where neighbour >= 0 && neighbour < lines.count {
                        if let value = lastMoney(in: lines[neighbour], decimals: decimals)?.value {
                            amount = value
                            break
                        }
                    }
                }
                if let amount, amount > (best ?? 0) { best = amount }
            }
            if let best { return (minorUnits(from: best, decimals: decimals), true) }
        }

        // Fallback: the largest money amount anywhere (low confidence).
        var fallback: Decimal?
        for line in lines {
            if let amount = lastMoney(in: line, decimals: decimals)?.value, amount > (fallback ?? 0) {
                fallback = amount
            }
        }
        if let fallback { return (minorUnits(from: fallback, decimals: decimals), false) }
        return (nil, false)
    }

    private static func minorUnits(from value: Decimal, decimals: Int) -> Int {
        let scaled = (value * Decimal.powerOfTen(decimals)).rounded(scale: 0)
        return NSDecimalNumber(decimal: scaled).intValue
    }

    // MARK: - Number extraction

    private static let numberRegex = try! NSRegularExpression(
        pattern: "\\d[\\d.,]*\\d|\\d"
    )

    /// Interprets a numeric token as a money amount **only if** it has exactly the
    /// currency's decimal places (e.g. for USD, "489.00" yes; "10.5" shoe size no;
    /// "1104" card digits no). This is what separates real prices from the sizes,
    /// quantities, phone numbers and card fragments that litter receipt OCR.
    private static func moneyValue(_ token: String, decimals: Int) -> Decimal? {
        let cleaned = token.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !cleaned.isEmpty else { return nil }
        if decimals > 0 {
            guard let lastSep = cleaned.lastIndex(where: { $0 == "." || $0 == "," }) else { return nil }
            let fraction = cleaned[cleaned.index(after: lastSep)...]
            guard fraction.count == decimals, fraction.allSatisfy(\.isNumber) else { return nil }
        }
        return parseDecimal(token)
    }

    /// The last money amount on a line and its character range (for splitting the name off).
    private static func lastMoney(in line: String, decimals: Int) -> (value: Decimal, range: NSRange)? {
        let ns = line as NSString
        let matches = numberRegex.matches(in: line, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            if let value = moneyValue(ns.substring(with: match.range), decimals: decimals) {
                return (value, match.range)
            }
        }
        return nil
    }

    /// Normalizes a localized number token ("1,234.56", "1.234,56", "12,50") to Decimal.
    static func parseDecimal(_ token: String) -> Decimal? {
        var s = token.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !s.isEmpty else { return nil }
        let hasDot = s.contains("."), hasComma = s.contains(",")

        if hasDot && hasComma {
            let dotLast = s.lastIndex(of: ".")! > s.lastIndex(of: ",")!
            if dotLast {
                s.removeAll { $0 == "," }                 // comma = thousands
            } else {
                s.removeAll { $0 == "." }                 // dot = thousands
                s = s.replacingOccurrences(of: ",", with: ".")
            }
        } else if hasComma {
            let parts = s.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 2 && parts[1].count <= 2 {
                s = s.replacingOccurrences(of: ",", with: ".")   // decimal comma
            } else {
                s.removeAll { $0 == "," }                          // thousands comma
            }
        } else if hasDot {
            let parts = s.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count > 2 || (parts.count == 2 && parts[1].count == 3) {
                s.removeAll { $0 == "." }                          // thousands dot(s)
            }
        }
        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }

    // MARK: - Line items

    // Lines that are payment/summary rows, never a purchased item.
    private static let itemExclusions: [String] = [
        "subtotal", "sub total", "total", "tax", "vat", "gst", "tip", "gratuity",
        "balance", "amount", "change", "cash", "tendered", "card", "visa",
        "mastercard", "debit", "credit", "approved", "savings", "discount",
        "points", "to pay", "receipt", "associate", "purchase",
    ]

    private static let nameTrimChars = CharacterSet(charactersIn: " \t-:•·*$€£¥₹")

    private static func isExcludedLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return itemExclusions.contains { lower.contains($0) }
    }

    private static func looksLikeName(_ line: String, decimals: Int) -> Bool {
        line.filter { $0.isLetter }.count >= 3
            && !isExcludedLine(line)
            && lastMoney(in: line, decimals: decimals) == nil
    }

    /// Extracts purchased lines as (description, price). Real receipt OCR puts the
    /// amount column on its own lines, in either order relative to the description
    /// (price-above-name for one item, name-above-price for the next). So each
    /// money line is paired with an adjacent description line on whichever side
    /// has one. Summary/payment amounts are dropped because their neighbours are
    /// excluded labels rather than item descriptions.
    private static func detectLineItems(lines: [String], decimals: Int) -> [ReceiptLineItem] {
        var items: [ReceiptLineItem] = []
        var usedAsName = Set<Int>()

        for (index, line) in lines.enumerated() {
            if isExcludedLine(line) { continue }
            guard let money = lastMoney(in: line, decimals: decimals) else { continue }

            let ns = line as NSString
            let before = ns.substring(to: money.range.location).trimmingCharacters(in: nameTrimChars)
            let after = ns.substring(from: money.range.location + money.range.length).trimmingCharacters(in: nameTrimChars)

            var name: String
            if before.filter({ $0.isLetter }).count >= 3 {
                name = before                                   // inline: "Premium sneaker cleaner x1 $32.99"
            } else {
                // The amount stands alone (maybe with a quantity like "x1") — borrow
                // the description from an adjacent, unused, non-excluded line.
                let quantity = (before + " " + after).trimmingCharacters(in: .whitespaces)
                var borrowed: String?
                for neighbour in [index - 1, index + 1] {
                    guard neighbour >= 0, neighbour < lines.count, !usedAsName.contains(neighbour) else { continue }
                    guard looksLikeName(lines[neighbour], decimals: decimals) else { continue }
                    borrowed = lines[neighbour]
                    usedAsName.insert(neighbour)
                    break
                }
                guard let borrowed else { continue }            // no description nearby → not a real item
                name = quantity.isEmpty ? borrowed : "\(borrowed) \(quantity)"
            }

            name = name.trimmingCharacters(in: nameTrimChars)
            guard name.filter({ $0.isLetter }).count >= 2 else { continue }
            items.append(ReceiptLineItem(name: name, amountMinor: minorUnits(from: money.value, decimals: decimals)))
        }
        return items
    }

    // MARK: - Merchant

    private static func detectMerchant(lines: [String]) -> String? {
        for line in lines.prefix(6) {
            let lower = line.lowercased()
            guard line.count >= 2, line.count <= 40 else { continue }
            guard line.contains(where: { $0.isLetter }) else { continue }
            // Skip lines starting with a digit — addresses, dates, receipt numbers.
            guard let first = line.first, !first.isNumber else { continue }
            guard !merchantNoise.contains(where: { lower.contains($0) }) else { continue }
            // Skip lines that are mostly digits (phone numbers, codes).
            let digits = line.filter { $0.isNumber }.count
            guard digits * 2 < line.count else { continue }
            return line
        }
        return nil
    }

    // MARK: - Date

    private static func detectDate(in text: String) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let ns = text as NSString
        let matches = detector?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []
        let now = Date()
        let dates = matches.compactMap { $0.date }
        // Prefer the most recent date that isn't in the future (receipts are past-dated).
        let past = dates.filter { $0 <= now }
        return past.max() ?? dates.first
    }
}
