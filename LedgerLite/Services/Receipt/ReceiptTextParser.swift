import Foundation

/// Stateless heuristics that turn a receipt's OCR text into a `ParsedReceipt`.
/// No Vision, no SwiftData, no SwiftUI — pure and fully unit-testable, mirroring
/// `SubscriptionDetector`. The OCR step lives in `ReceiptScanner`; keeping it out
/// of here means all the real logic is covered without needing real images.
enum ReceiptTextParser {

    // Shared with SubscriptionDetector via Constants — see currencySymbolMap.
    // "RM" (Malaysian Ringgit) is handled separately in detectCurrency with a
    // word boundary, so it can't fire inside "SUPERMARKET" or "FARM 3.00".
    private static let symbolMap = Constants.App.currencySymbolMap

    // Strongest first — a "grand total" beats a bare "total" beats "amount".
    private static let totalKeywordTiers: [[String]] = [
        ["grand total", "total due", "amount due", "balance due", "total to pay",
         "amount to pay", "total a pagar", "zu zahlen", "gesamtbetrag"],
        ["total", "balance", "to pay", "summe", "gesamt", "totaal", "toplam"],
        ["amount", "montant"],
    ]

    // Lines whose total-like number must be ignored — they are not the bill total.
    private static let totalExclusions: [String] = [
        "subtotal", "sub total", "tax", "vat", "gst", "tip", "gratuity",
        "change", "cash", "tendered", "savings", "discount", "points",
        "val. total", "val total", "base imp",
        // de/fr/es/pt/it/nl/tr: subtotal, VAT, discount, change, tip.
        "zwischensumme", "mwst", "tva", "btw", "kdv", "rabatt", "remise",
        "descuento", "desconto", "sconto", "korting", "rückgeld", "ruckgeld",
        "trinkgeld", "propina", "pourboire", "wisselgeld",
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

        // The labeled total row, when present, also bounds the item search:
        // promo details, payment rows and VAT summaries printed after it can
        // never be items (this is what stops a discount being counted twice).
        let labeled = detectLabeledTotal(lines: lines, decimals: decimals)

        // Reconcile line items by the universal invariant — items (including
        // negative discounts) sum to the (sub)total. This ends the item list in
        // any language and yields a language-agnostic total fallback.
        let reconciled = reconcileItems(lines: lines, decimals: decimals, totalRow: labeled?.row)

        let tax = detectAddOnTax(
            lines: lines, decimals: decimals, totalRow: labeled?.row,
            items: reconciled.items, labeledTotal: labeled?.minor,
            reconciledTotal: reconciled.total
        )

        let amount: Int?
        let confident: Bool
        if let labeled {
            (amount, confident) = (labeled.minor, true)
        } else if let total = reconciled.total {
            (amount, confident) = (total, true)
        } else {
            (amount, confident) = (largestAmount(lines: lines, decimals: decimals), false)
        }

        return ParsedReceipt(
            amountMinor: amount,
            currencyCode: currency,
            merchant: detectMerchant(lines: lines),
            date: detectDate(in: text),
            amountConfident: confident,
            lineItems: reconciled.items,
            tax: tax,
            rawText: text
        )
    }

    // MARK: - Currency

    private static func detectCurrency(in text: String) -> String? {
        for entry in symbolMap where text.contains(entry.symbol) {
            return entry.code
        }
        // "RM" (Malaysian Ringgit) is alphabetic, so it's matched only when it
        // prefixes a number at a word boundary — a plain substring check would
        // fire on "SUPERMARKET" or "FARM 3.00".
        if text.range(of: "\\bRM\\s?\\d", options: .regularExpression) != nil { return "MYR" }
        // ISO code appearing as a standalone token, e.g. "EUR 12.00". A word
        // boundary is required so "CAD" isn't matched inside "Arcade".
        let upper = text.uppercased()
        for code in Constants.App.supportedCurrencies
        where upper.range(of: "\\b\(code)\\b", options: .regularExpression) != nil {
            return code
        }
        return nil
    }

    // MARK: - Total

    /// Finds an explicitly labeled total and the row it lives on.
    /// Vision often splits a "Total" label and its amount onto separate lines in
    /// either order, so the amount is looked for on the same line and both
    /// neighbours. When several rows tie on the best amount (duplicate total
    /// sections), the **last** row wins, so the item cut covers all of them.
    private static func detectLabeledTotal(lines: [String], decimals: Int) -> (minor: Int, row: Int)? {
        for tier in totalKeywordTiers {
            var best: (value: Decimal, row: Int)?
            for (index, line) in lines.enumerated() {
                let lower = line.lowercased()
                guard tier.contains(where: { lower.contains($0) }) else { continue }
                guard !totalExclusions.contains(where: { lower.contains($0) }) else { continue }

                var amount = lastMoney(in: line, decimals: decimals)?.value
                var amountRow = index
                if amount == nil {
                    for neighbour in [index + 1, index - 1] where neighbour >= 0 && neighbour < lines.count {
                        if let value = lastMoney(in: lines[neighbour], decimals: decimals)?.value {
                            amount = value
                            amountRow = max(index, neighbour)
                            break
                        }
                    }
                }
                if let amount, amount >= (best?.value ?? 0) {
                    best = (amount, amountRow)
                }
            }
            if let best { return (minorUnits(from: best.value, decimals: decimals), best.row) }
        }
        return nil
    }

    /// Last resort when no label matched and the items didn't reconcile:
    /// the largest money amount anywhere (low confidence).
    private static func largestAmount(lines: [String], decimals: Int) -> Int? {
        var fallback: Decimal?
        for line in lines {
            if let amount = lastMoney(in: line, decimals: decimals)?.value, amount > (fallback ?? 0) {
                fallback = amount
            }
        }
        return fallback.map { minorUnits(from: $0, decimals: decimals) }
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

    // Rows that are summary / payment / tax lines, never a purchased item —
    // excluded even when negative (change is often printed negative). Includes
    // non-English terms common on European receipts.
    private static let paymentExclusions: [String] = [
        "subtotal", "sub total", "total", "tax", "vat", "gst", "tip", "gratuity",
        "balance", "amount", "change", "cash", "tendered", "card", "visa",
        "mastercard", "debit", "credit", "approved", "to pay", "receipt",
        "associate", "purchase",
        // Non-English (pt/es/fr/de/it/nl/tr): cash, change, VAT, tax base, per-unit.
        "dinheiro", "troco", "efectivo", "cambio", "iva", "base imp", "importe",
        "/kg", "kg x", "x 1,", "x 0,", "€/kg", "eur/kg",
        "zwischensumme", "mwst", "tva", "btw", "kdv", "rückgeld", "ruckgeld",
        "bargeld", "wechselgeld", "wisselgeld", "girocard", "kontaktlos",
        "contanti", "tarjeta", "carte", "espèces", "especes", "rendu", "nakit",
        "trinkgeld", "propina", "pourboire",
    ]

    // Discount / promotion rows. Excluded only when printed **positive** — US
    // "TOTAL SAVINGS 5.00" is informational (already baked into item prices).
    // When explicitly negative they are real subtractions and become negative
    // line items, so the breakdown still sums to the charged total.
    private static let discountKeywords: [String] = [
        "discount", "savings", "saving", "promo", "coupon", "voucher", "loyalty",
        "points", "rabatt", "remise", "descuento", "desconto", "sconto", "korting",
    ]

    // Add-on tax rows (US-style, tax charged on top of item prices).
    private static let taxKeywords: [String] = [
        "sales tax", "tax", "vat", "gst", "mwst", "iva", "tva", "btw", "kdv",
    ]

    private static let nameTrimChars = CharacterSet(charactersIn: " \t-−:•·*$€£¥₹()")

    /// Per-unit / weight rows ("0,540 kg x 1,49 EUR/kg") — structural, not items.
    private static func isUnitPriceRow(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("kg") || lower.contains("/kg") || lower.contains("/lb") || lower.contains("€/")
    }

    /// True when the amount at `range` is explicitly negative: a leading minus
    /// ("-2.20"), a trailing minus ("0,55-", German style), or accounting
    /// parentheses ("(2.00)", US style).
    private static func isNegativeAmount(in line: String, at range: NSRange) -> Bool {
        let ns = line as NSString
        let before = ns.substring(to: range.location)
        let after = ns.substring(from: range.location + range.length)
        let beforeStripped = before.trimmingCharacters(in: CharacterSet(charactersIn: " \t$€£¥₹"))
        if beforeStripped.hasSuffix("-") || beforeStripped.hasSuffix("−") { return true }
        // Trailing minus: attached ("0,55-") or alone at the end of the row.
        if after.hasPrefix("-") || after.hasPrefix("−") { return true }
        if after.trimmingCharacters(in: .whitespaces) == "-" { return true }
        if beforeStripped.hasSuffix("("),
           after.trimmingCharacters(in: .whitespaces).hasPrefix(")") { return true }
        return false
    }

    /// Reconciles line items by the universal invariant: **items (including
    /// negative discounts) sum to the (sub)total**. From the geometry-
    /// reconstructed rows it takes each "DESCRIPTION … PRICE" row (3+ letters of
    /// description) as a candidate, then collects them in order until a positive
    /// candidate's amount equals the running sum — that candidate is the
    /// (sub)total, and everything after it (tax, cash, change, in any language)
    /// is dropped without needing keywords for it.
    ///
    /// `totalRow` — the labeled total's row when one was found — bounds the
    /// search: rows printed after the total (promo details, payment, VAT
    /// summaries) are never items, which prevents double-counting a discount
    /// that is itemized again in a promotions section.
    ///
    /// Known summary terms are still excluded up front, which both covers the
    /// common case and prevents them from polluting the running sum. When the sum
    /// never reconciles (e.g. an OCR error in a price), it degrades to "every
    /// non-summary candidate is an item", i.e. the previous behaviour.
    ///
    /// Returns the items and, when reconciliation succeeded, the amount they summed
    /// to — used as a language-agnostic total fallback.
    private static func reconcileItems(
        lines: [String], decimals: Int, totalRow: Int?
    ) -> (items: [ReceiptLineItem], total: Int?) {
        var candidates: [(name: String, minor: Int)] = []
        let end = min(totalRow ?? lines.count, lines.count)
        for line in lines[..<end] {
            if isUnitPriceRow(line) { continue }
            guard let money = lastMoney(in: line, decimals: decimals) else { continue }

            let lower = line.lowercased()
            if paymentExclusions.contains(where: { lower.contains($0) }) { continue }

            let negative = isNegativeAmount(in: line, at: money.range)
            // Positive-printed discount/savings rows are informational; only an
            // explicit negative is a real subtraction worth capturing.
            if !negative, discountKeywords.contains(where: { lower.contains($0) }) { continue }

            let ns = line as NSString
            let name = ns.substring(to: money.range.location).trimmingCharacters(in: nameTrimChars)
            guard name.filter({ $0.isLetter }).count >= 3 else { continue }

            let minor = minorUnits(from: money.value, decimals: decimals)
            candidates.append((name, negative ? -minor : minor))
        }

        var collected: [(name: String, minor: Int)] = []
        var runningSum = 0
        var reconciledTotal: Int?
        for candidate in candidates {
            // A positive row equal to the running sum of prior items is the
            // (sub)total — stop. (A discount can never be the total.)
            if candidate.minor > 0, collected.count >= 2, abs(candidate.minor - runningSum) <= 1 {
                reconciledTotal = candidate.minor
                break
            }
            collected.append(candidate)
            runningSum += candidate.minor
        }

        let items = collected.map { ReceiptLineItem(name: $0.name, amountMinor: $0.minor) }
        return (items, reconciledTotal)
    }

    // MARK: - Add-on tax

    /// Captures US-style add-on tax, but **only** when the arithmetic proves it:
    /// items (+ discounts) + tax must equal the labeled total. Price-inclusive
    /// VAT summaries (EU receipts) fail that check — their items already sum to
    /// the total — so they are never double-counted. Multiple tax rows (state +
    /// city) are summed under a generic "Tax" label.
    private static func detectAddOnTax(
        lines: [String], decimals: Int, totalRow: Int?,
        items: [ReceiptLineItem], labeledTotal: Int?, reconciledTotal: Int?
    ) -> ReceiptLineItem? {
        // Run when the items did not reconcile to the labeled total: either no
        // subtotal was found (reconciledTotal == nil) or an unlabeled subtotal
        // reconciled to a value below the total, leaving room for add-on tax.
        // The arithmetic guard below (items + tax == total) is the real safety
        // net against double-counting price-inclusive VAT.
        guard let labeledTotal, let totalRow, !items.isEmpty,
              reconciledTotal == nil || reconciledTotal != labeledTotal else { return nil }

        var taxRows: [(name: String, minor: Int)] = []
        for line in lines[..<min(totalRow, lines.count)] {
            let lower = line.lowercased()
            guard taxKeywords.contains(where: { lower.contains($0) }) else { continue }
            guard let money = lastMoney(in: line, decimals: decimals) else { continue }
            guard !isNegativeAmount(in: line, at: money.range) else { continue }
            let ns = line as NSString
            let name = ns.substring(to: money.range.location).trimmingCharacters(in: nameTrimChars)
            taxRows.append((name.isEmpty ? "Tax" : name, minorUnits(from: money.value, decimals: decimals)))
        }
        guard !taxRows.isEmpty else { return nil }

        let taxSum = taxRows.reduce(0) { $0 + $1.minor }
        let itemsSum = items.reduce(0) { $0 + $1.amountMinor }
        guard taxSum > 0, abs(itemsSum + taxSum - labeledTotal) <= 1 else { return nil }

        let name = taxRows.count == 1 ? taxRows[0].name : "Tax"
        return ReceiptLineItem(name: name, amountMinor: taxSum)
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
