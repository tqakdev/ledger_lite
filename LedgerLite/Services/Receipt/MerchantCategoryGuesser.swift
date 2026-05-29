import Foundation

/// Guesses a category name for a scanned merchant. Pure and testable: callers
/// pass the user's recent (merchant, category) history and the set of category
/// names that currently exist.
///
/// Strategy:
///   1. **History first** — if the user has logged this merchant before, reuse
///      that category. Personalized, private, zero-config.
///   2. **Keyword fallback** — a small built-in map of merchant tokens.
/// Returns `nil` when nothing matches, so the form keeps its default.
enum MerchantCategoryGuesser {

    /// Ordered most-specific-first; the first category with a token contained in
    /// the merchant wins. Category names match LedgerLite's default seeds.
    private static let keywordMap: [(category: String, tokens: [String])] = [
        ("Groceries", ["supermarket", "grocery", "market", "mart", "tesco", "aldi",
                       "lidl", "kroger", "costco", "safeway", "trader joe", "whole foods"]),
        ("Food", ["coffee", "cafe", "café", "restaurant", "pizza", "burger", "sushi",
                  "grill", "kitchen", "bakery", "deli", "diner", "bistro", "starbucks",
                  "mcdonald", "kfc", "subway", "pret", "chipotle", "taco"]),
        ("Transport", ["uber", "lyft", "taxi", "transit", "metro", "shell", "exxon",
                       "chevron", "fuel", "gas station", "parking", "toll"]),
        ("Health", ["pharmacy", "drug", "cvs", "walgreens", "clinic", "dental",
                    "hospital", "fitness", "gym"]),
        ("Travel", ["hotel", "airbnb", "airline", "airways", "flight", "expedia",
                    "booking", "motel", "inn"]),
        ("Entertainment", ["cinema", "movie", "theater", "theatre", "netflix",
                           "spotify", "steam", "playstation", "xbox"]),
        ("Bills", ["electric", "utility", "internet", "comcast", "verizon",
                   "telecom", "mobile"]),
        ("Shopping", ["amazon", "apple store", "nike", "zara", "ikea", "target",
                      "best buy", "mall", "store"]),
    ]

    static func guess(
        merchant: String,
        history: [(merchant: String, categoryName: String)],
        available: Set<String>
    ) -> String? {
        let needle = normalize(merchant)
        guard !needle.isEmpty else { return nil }

        // 1. History — exact-ish match on a previously categorized merchant.
        for entry in history {
            let known = normalize(entry.merchant)
            guard !known.isEmpty else { continue }
            if known == needle || needle.contains(known) || known.contains(needle) {
                if available.contains(entry.categoryName) { return entry.categoryName }
            }
        }

        // 2. Keyword fallback.
        for entry in keywordMap where available.contains(entry.category) {
            if entry.tokens.contains(where: { needle.contains($0) }) {
                return entry.category
            }
        }
        return nil
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
