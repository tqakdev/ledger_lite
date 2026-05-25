import Foundation

// MARK: - BillingCycle

/// Billing cadence for a subscription.
/// Stored as a raw `String` in SwiftData; this enum bridges the raw string to typed cases.
enum BillingCycle: Hashable {
    case weekly
    case monthly
    case yearly
    case customDays(Int)   // Int must be > 0; enforced in init?(rawValue:)

    var rawValue: String {
        switch self {
        case .weekly:            return "weekly"
        case .monthly:           return "monthly"
        case .yearly:            return "yearly"
        case .customDays(let n): return "customDays:\(n)"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "weekly":   self = .weekly
        case "monthly":  self = .monthly
        case "yearly":   self = .yearly
        default:
            // Require exact prefix, non-empty numeric suffix, positive integer, no extra content.
            // "customDays:0", "customDays:-5", "customDays:", "customDays:abc",
            // "customDays:30:extra", "CustomDays:30" all return nil.
            guard rawValue.hasPrefix("customDays:") else { return nil }
            let suffix = rawValue.dropFirst("customDays:".count)
            guard !suffix.isEmpty,
                  let n = Int(suffix),   // Int() rejects "abc", "30:extra", empty string
                  n > 0                  // rejects 0 and negatives
            else { return nil }
            self = .customDays(n)
        }
    }

    /// Approximate monthly factor for "true monthly cost" display.
    /// Uses Decimal arithmetic throughout — never Double.
    var monthlyFactor: Decimal {
        switch self {
        case .weekly:            return Decimal(52) / Decimal(12)   // ≈ 4.333
        case .monthly:           return 1
        case .yearly:            return Decimal(1) / Decimal(12)    // ≈ 0.0833
        case .customDays(let n): return Decimal(30) / Decimal(n)
        }
    }

    /// Advances `date` by exactly one billing cycle using calendar arithmetic.
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        case .customDays(let n):
            return calendar.date(byAdding: .day, value: n, to: date) ?? date
        }
    }
}

extension BillingCycle: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let cycle = BillingCycle(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid BillingCycle raw value: \(raw)"
            )
        }
        self = cycle
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - SubscriptionStatus

enum SubscriptionStatus: String, Hashable, Codable, CaseIterable {
    case active    = "active"
    case paused    = "paused"
    case cancelled = "cancelled"
}

// MARK: - ExpenseSource

enum ExpenseSource: String, Hashable, Codable, CaseIterable {
    case manual       = "manual"
    case subscription = "subscription"
    case widget       = "widget"
    case siri         = "siri"
}
