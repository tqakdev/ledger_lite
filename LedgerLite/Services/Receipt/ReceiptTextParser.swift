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
    private static func detectTotal(lines: [String], decimals: Int) -> (Int?, Bool) {
        for tier in totalKeywordTiers {
            var best: Decimal?
            for (index, line) in lines.enumerated() {
                let lower = line.lowercased()
                guard tier.contains(where: { lower.contains($0) }) else { continue }
                guard !totalExclusions.contains(where: { lower.contains($0) }) else { continue }

                // The amount is usually on the same line; if not, look at the next.
                var amount = largestPriceLikeAmount(in: line)
                if amount == nil, index + 1 < lines.count {
                    amount = largestPriceLikeAmount(in: lines[index + 1])
                }
                if let amount, amount > (best ?? 0) { best = amount }
            }
            if let best { return (minorUnits(from: best, decimals: decimals), true) }
        }

        // Fallback: the largest price-like number anywhere (low confidence).
        var fallback: Decimal?
        for line in lines {
            if let amount = largestPriceLikeAmount(in: line), amount > (fallback ?? 0) {
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

    /// All numeric tokens on a line, paired with whether the token looks like a
    /// price (has a fractional part). Prefers price-looking tokens so a card
    /// number or quantity doesn't masquerade as the total.
    private static func largestPriceLikeAmount(in line: String) -> Decimal? {
        let ns = line as NSString
        let matches = numberRegex.matches(in: line, range: NSRange(location: 0, length: ns.length))
        var priced: [Decimal] = []
        var plain: [Decimal] = []
        for match in matches {
            let token = ns.substring(with: match.range)
            guard let value = parseDecimal(token) else { continue }
            if token.contains(".") || token.contains(",") {
                priced.append(value)
            } else {
                plain.append(value)
            }
        }
        return priced.max() ?? plain.max()
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

    /// Extracts purchased lines: a description followed by a price. Summary and
    /// payment rows are excluded. Item names may be slightly truncated when the
    /// description wraps across OCR lines — the price line is what's captured.
    private static func detectLineItems(lines: [String], decimals: Int) -> [ReceiptLineItem] {
        var items: [ReceiptLineItem] = []
        for line in lines {
            let lower = line.lowercased()
            guard !itemExclusions.contains(where: { lower.contains($0) }) else { continue }

            let ns = line as NSString
            let matches = numberRegex.matches(in: line, range: NSRange(location: 0, length: ns.length))
            // The price is the last token with a fractional part.
            guard let priceMatch = matches.last(where: { match in
                let token = ns.substring(with: match.range)
                return token.contains(".") || token.contains(",")
            }) else { continue }

            let token = ns.substring(with: priceMatch.range)
            guard let value = parseDecimal(token) else { continue }

            var name = ns.substring(to: priceMatch.range.location)
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t-:•·*$€£¥₹"))
            // Need a real description, not just stray punctuation.
            guard name.contains(where: { $0.isLetter }), name.count >= 2 else { continue }
            name = name.trimmingCharacters(in: .whitespaces)

            items.append(ReceiptLineItem(name: name, amountMinor: minorUnits(from: value, decimals: decimals)))
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
