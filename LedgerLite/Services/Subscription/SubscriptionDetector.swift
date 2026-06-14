import Foundation

/// Stateless text-pattern detector — no SwiftData, no network, no @MainActor requirement.
/// Feed it raw text (email body, SMS, receipt) and get back scored subscription candidates.
enum SubscriptionDetector {

    // MARK: - Thresholds (referenced by SubscriptionCandidate.ConfidenceTier)

    static let noiseThreshold: Double  = 0.40
    static let dimThreshold: Double    = 0.65
    static let strongThreshold: Double = 0.75

    // MARK: - Known services

    static let knownServices: [String] = [
        "Netflix", "Spotify", "Apple Music", "Apple TV+", "Apple Arcade", "Apple One",
        "iCloud+", "Disney+", "Hulu", "HBO Max", "Amazon Prime", "YouTube Premium",
        "YouTube TV", "Google One", "Microsoft 365", "Xbox Game Pass", "PlayStation Plus",
        "Nintendo Switch Online", "Twitch", "Patreon", "Adobe Creative Cloud", "Dropbox",
        "Notion", "Slack", "Zoom", "1Password", "NordVPN", "Duolingo", "Headspace",
        "Calm", "Peloton", "Strava", "Grammarly", "Canva", "Figma", "GitHub",
        "OpenAI", "ChatGPT", "Claude", "LinkedIn Premium", "Tidal", "Deezer",
    ]

    // MARK: - Internal constants

    // Shared with ReceiptTextParser via Constants — see currencySymbolMap.
    // "RM" (Malaysian Ringgit) is handled separately in extractAmount with a
    // word boundary, so it can't fire inside "FARM 9.99".
    private static let symbolMap = Constants.App.currencySymbolMap

    private static let subscriptionKeywords: [String] = [
        "subscription", "subscribe", "renewal", "renew", "billing", "billed",
        "charged", "invoice", "recurring", "plan", "membership", "premium",
    ]

    private static let genericNames: Set<String> = [
        "plan", "subscription", "membership", "billing", "service",
    ]

    // Words excluded from name extraction because they are document labels, not service names.
    private static let noiseWords: Set<String> = [
        "USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "INR", "KRW",
        "SGD", "HKD", "NZD", "SEK", "NOK", "DKK",
        "The", "Your", "You", "For", "From", "To", "At", "Hi", "Dear",
        "Amount", "Total", "Charge", "Payment", "Receipt", "Invoice", "Due",
    ]

    // MARK: - Public API

    /// Detects subscription candidates in arbitrary text.
    /// Candidates below `noiseThreshold` are filtered; results are deduplicated by name
    /// and sorted by confidence descending.
    static func detect(in text: String) -> [SubscriptionCandidate] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let lines = text.components(separatedBy: .newlines)
        var raw: [SubscriptionCandidate] = []

        for (index, line) in lines.enumerated() {
            guard let (amountMinor, currencyCode) = extractAmount(from: line) else { continue }

            // Context window (±3 lines) for name/cycle/keyword extraction
            let start   = max(0, index - 3)
            let end     = min(lines.count - 1, index + 3)
            let context = lines[start...end].joined(separator: " ")

            let name = extractName(from: context, amountLine: line)
            guard !name.isEmpty else { continue }

            let cycle = extractBillingCycle(from: context)
            let score = scoreConfidence(
                amountMinor: amountMinor,
                name: name,
                cycle: cycle,
                context: context
            )
            guard score >= noiseThreshold else { continue }

            let detectedDate = extractNextBillingDate(from: context)
            raw.append(SubscriptionCandidate(
                name: name,
                amountMinor: amountMinor,
                currencyCode: currencyCode,
                billingCycle: cycle,
                confidence: score,
                detectedNextBillingDate: detectedDate
            ))
        }

        // Deduplicate by lowercased name — keep highest-confidence entry
        var seen: [String: SubscriptionCandidate] = [:]
        for c in raw {
            let key = c.name.lowercased()
            if let existing = seen[key] {
                if c.confidence > existing.confidence { seen[key] = c }
            } else {
                seen[key] = c
            }
        }

        return Array(seen.values).sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Amount extraction (internal for unit-test access)

    /// Returns the first recognisable monetary amount in `line` as (minorUnits, currencyCode).
    /// Tries symbol prefix → ISO prefix → ISO suffix, in that order.
    static func extractAmount(from line: String) -> (minorUnits: Int, currencyCode: String)? {
        // 1. Currency symbol prefix (e.g. "$9.99", "€9.99", "¥1500")
        for (symbol, code) in symbolMap {
            let escaped = NSRegularExpression.escapedPattern(for: symbol)
            let pattern = "\(escaped)\\s?(\\d+[.,]?\\d*)"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  match.numberOfRanges > 1,
                  let numRange = Range(match.range(at: 1), in: line)
            else { continue }
            let numStr = String(line[numRange])
            if let minor = parseMinorUnits(numStr, currencyCode: code) {
                return (minor, code)
            }
        }

        // 1b. "RM" (Malaysian Ringgit) — alphabetic, so require a word boundary
        //     to avoid matching inside words like "FARM 9.99" or "WARM 5.00".
        if let regex = try? NSRegularExpression(pattern: "\\bRM\\s?(\\d+[.,]?\\d*)"),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           match.numberOfRanges > 1,
           let numRange = Range(match.range(at: 1), in: line) {
            let numStr = String(line[numRange])
            if let minor = parseMinorUnits(numStr, currencyCode: "MYR") {
                return (minor, "MYR")
            }
        }

        // 2. ISO code prefix (e.g. "USD 9.99")
        let isoPrefix = "\\b([A-Z]{3})\\s+(\\d+[.,]?\\d*)"
        if let regex = try? NSRegularExpression(pattern: isoPrefix),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           match.numberOfRanges > 2,
           let codeRange = Range(match.range(at: 1), in: line),
           let numRange  = Range(match.range(at: 2), in: line) {
            let code   = String(line[codeRange])
            let numStr = String(line[numRange])
            if Constants.App.supportedCurrencies.contains(code),
               let minor = parseMinorUnits(numStr, currencyCode: code) {
                return (minor, code)
            }
        }

        // 3. ISO code suffix (e.g. "9.99 EUR")
        let isoSuffix = "\\b(\\d+[.,]?\\d*)\\s+([A-Z]{3})\\b"
        if let regex = try? NSRegularExpression(pattern: isoSuffix),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           match.numberOfRanges > 2,
           let numRange  = Range(match.range(at: 1), in: line),
           let codeRange = Range(match.range(at: 2), in: line) {
            let code   = String(line[codeRange])
            let numStr = String(line[numRange])
            if Constants.App.supportedCurrencies.contains(code),
               let minor = parseMinorUnits(numStr, currencyCode: code) {
                return (minor, code)
            }
        }

        return nil
    }

    // MARK: - Billing cycle extraction (internal for unit-test access)

    static func extractBillingCycle(from text: String) -> BillingCycle {
        let lower = text.lowercased()

        // "every N days" → .customDays(N)
        let everyDays = "every\\s+(\\d+)\\s+days?"
        if let regex = try? NSRegularExpression(pattern: everyDays),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           match.numberOfRanges > 1,
           let nRange = Range(match.range(at: 1), in: lower),
           let n = Int(String(lower[nRange])), n > 0 {
            return .customDays(n)
        }

        // "every N weeks" → .customDays(N * 7)
        let everyWeeks = "every\\s+(\\d+)\\s+weeks?"
        if let regex = try? NSRegularExpression(pattern: everyWeeks),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           match.numberOfRanges > 1,
           let nRange = Range(match.range(at: 1), in: lower),
           let n = Int(String(lower[nRange])), n > 0 {
            return .customDays(n * 7)
        }

        if lower.contains("annual") || lower.contains("yearly") ||
           lower.contains("per year") || lower.contains("/year") ||
           lower.contains("every year") {
            return .yearly
        }

        if lower.contains("weekly") || lower.contains("per week") || lower.contains("/week") {
            return .weekly
        }

        return .monthly
    }

    // MARK: - Name extraction (private)

    private static func extractName(from context: String, amountLine: String) -> String {
        // Priority 1a: known service on the same line as the amount (prevents context bleed
        //              when multiple service names appear in the ±3-line window)
        let lineLower = amountLine.lowercased()
        for service in knownServices {
            if lineLower.contains(service.lowercased()) { return service }
        }

        // Priority 1b: known service anywhere in the context window
        let lower = context.lowercased()
        for service in knownServices {
            if lower.contains(service.lowercased()) { return service }
        }

        // Priority 2: merchant / billed-by patterns
        let merchantPatterns = [
            "(?:from|merchant|billed by|billing for|charged by)\\s*:?\\s*([A-Z][\\w\\s]+?)(?:[,!\\n]|$)",
            "(?:your|the)\\s+([A-Z][\\w\\s]+?)\\s+(?:subscription|membership|plan)",
        ]
        for pattern in merchantPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: context, range: NSRange(context.startIndex..., in: context)),
                  match.numberOfRanges > 1,
                  let nameRange = Range(match.range(at: 1), in: context)
            else { continue }
            let name = String(context[nameRange]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, name.count <= 40 { return name }
        }

        // Priority 3: longest Title-Case word sequence on the amount line
        return extractCapitalisedSequence(from: amountLine)
    }

    private static func extractCapitalisedSequence(from line: String) -> String {
        let pattern = "\\b([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)*)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }

        let range   = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, range: range)

        let candidates = matches.compactMap { match -> String? in
            guard let r = Range(match.range, in: line) else { return nil }
            let word = String(line[r]).trimmingCharacters(in: .whitespaces)
            guard !noiseWords.contains(word), word.count >= 3 else { return nil }
            return word
        }

        return candidates.max(by: { $0.count < $1.count }) ?? ""
    }

    // MARK: - Confidence scoring (private)

    private static func scoreConfidence(
        amountMinor: Int,
        name: String,
        cycle: BillingCycle,
        context: String
    ) -> Double {
        var score: Double = 0.35  // base: parseable amount

        // Plausible subscription range in minor units: [50, 50_000] reads as
        // ¥50–¥50,000 for 0-decimal currencies and $0.50–$500.00 for 2-decimal ones,
        // so the same bounds apply regardless of the currency's decimal places.
        if amountMinor >= 50 && amountMinor <= 50_000 { score += 0.15 }

        // Known service name (+0.25)
        let nameLower = name.lowercased()
        if knownServices.contains(where: { $0.lowercased() == nameLower }) { score += 0.25 }

        // Billing-cycle keyword (+0.08–0.15)
        let lower = context.lowercased()
        switch cycle {
        case .monthly:
            if lower.contains("month") { score += 0.15 }
        case .yearly:
            score += 0.10
        case .weekly:
            score += 0.08
        case .customDays:
            score += 0.08
        }

        // Subscription-context keywords: +0.04 each, capped at +0.16
        var kwBoost: Double = 0
        for kw in subscriptionKeywords {
            if lower.contains(kw) {
                kwBoost += 0.04
                if kwBoost >= 0.16 { break }
            }
        }
        score += kwBoost

        // Non-generic name (+0.05)
        if !genericNames.contains(nameLower) { score += 0.05 }

        return min(1.0, score)
    }

    // MARK: - Next billing date extraction (internal for unit-test access)

    /// Scans `text` for a recognisable date string and returns a UTC-midnight Date.
    /// Supported patterns: ISO 8601 (2026-06-15), "June 15", "Jun 15", "June 15, 2026",
    /// "15 June", "15 June 2026". When only month+day is found, the year is inferred:
    /// current year if the date is still in the future, otherwise next year.
    static func extractNextBillingDate(from text: String) -> Date? {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let now    = Date()
        let locale = Locale(identifier: "en_US_POSIX")
        let utcTZ  = TimeZone(identifier: "UTC")!

        func makeFormatter(_ format: String) -> DateFormatter {
            let f = DateFormatter()
            f.dateFormat = format
            f.locale     = locale
            f.timeZone   = utcTZ
            return f
        }

        // Resolves a parsed date to UTC midnight, inferring year when absent.
        func utcMidnight(_ date: Date, hasYear: Bool) -> Date? {
            if hasYear { return utcCal.startOfDay(for: date) }
            var dc = utcCal.dateComponents([.month, .day], from: date)
            dc.year   = utcCal.component(.year, from: now)
            dc.hour   = 0; dc.minute = 0; dc.second = 0
            if let candidate = utcCal.date(from: dc), candidate > now { return candidate }
            dc.year = (dc.year ?? 0) + 1
            return utcCal.date(from: dc)
        }

        // 1. ISO 8601 — "2026-06-15"
        if let regex = try? NSRegularExpression(pattern: "\\b(\\d{4}-\\d{2}-\\d{2})\\b"),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(match.range(at: 1), in: text),
           let date = makeFormatter("yyyy-MM-dd").date(from: String(text[r])) {
            return date
        }

        // 2. Month-name before day — "June 15, 2026" / "Jun 15, 2026" / "June 15" / "Jun 15"
        if let regex = try? NSRegularExpression(
            pattern: "\\b([A-Za-z]{3,9}\\s+\\d{1,2}(?:,\\s*\\d{4})?)\\b"
        ) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r = Range(match.range(at: 1), in: text) else { continue }
                let str = String(text[r])
                let fmts: [(String, Bool)] = [
                    ("MMMM d, yyyy", true), ("MMM d, yyyy", true),
                    ("MMMM d",       false), ("MMM d",       false),
                ]
                for (fmt, hasYear) in fmts {
                    if let date = makeFormatter(fmt).date(from: str) {
                        return utcMidnight(date, hasYear: hasYear)
                    }
                }
            }
        }

        // 3. Day before month-name — "15 June 2026" / "15 June" / "15 Jun"
        if let regex = try? NSRegularExpression(
            pattern: "\\b(\\d{1,2}\\s+[A-Za-z]{3,9}(?:\\s+\\d{4})?)\\b"
        ) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r = Range(match.range(at: 1), in: text) else { continue }
                let str = String(text[r])
                let fmts: [(String, Bool)] = [
                    ("d MMMM yyyy", true), ("d MMM yyyy", true),
                    ("d MMMM",      false), ("d MMM",      false),
                ]
                for (fmt, hasYear) in fmts {
                    if let date = makeFormatter(fmt).date(from: str) {
                        return utcMidnight(date, hasYear: hasYear)
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Minor-unit parsing (private)

    private static func parseMinorUnits(_ raw: String, currencyCode: String) -> Int? {
        let places = Money.decimals(for: currencyCode)

        if places == 0 {
            // 0-decimal currencies (JPY, KRW): strip thousands commas and parse as integer
            let stripped = raw.replacingOccurrences(of: ",", with: "")
            guard let val = Int(stripped), val >= 0 else { return nil }
            return val
        }

        // Normalise decimal separator
        var normalized = raw
        if raw.contains(",") && !raw.contains(".") {
            let parts = raw.components(separatedBy: ",")
            if parts.count == 2, let frac = parts.last, frac.count == 2 {
                // Exactly 2 digits after comma → European decimal comma (e.g. €9,99)
                normalized = parts[0] + "." + parts[1]
            } else {
                // Thousands separator (e.g. 1,000) — strip
                normalized = raw.replacingOccurrences(of: ",", with: "")
            }
        }

        let parts = normalized.components(separatedBy: ".")
        guard let intVal = Int(parts[0].isEmpty ? "0" : parts[0]) else { return nil }
        let multiplier = pow10(places)
        // A long digit run in OCR/email text (e.g. an account number) can overflow
        // when scaled to minor units. Such a value is never a plausible price, so
        // treat overflow as "not a money amount" rather than trapping.
        let (scaled, scaledOverflow) = intVal.multipliedReportingOverflow(by: multiplier)
        guard !scaledOverflow else { return nil }

        if parts.count > 1 {
            let fracStr = String(parts[1].prefix(places))
                .padding(toLength: places, withPad: "0", startingAt: 0)
            guard let fracVal = Int(fracStr) else { return nil }
            let (sum, sumOverflow) = scaled.addingReportingOverflow(fracVal)
            guard !sumOverflow else { return nil }
            return sum
        }
        return scaled
    }

    private static func pow10(_ n: Int) -> Int {
        guard n > 0 else { return 1 }
        return (0..<n).reduce(1) { acc, _ in acc * 10 }
    }
}
