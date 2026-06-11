import Testing
import Foundation
@testable import LedgerLite

// MARK: - Helpers

private func makeCategories(_ names: [String]) -> [LedgerLite.Category] {
    names.enumerated().map { index, name in
        LedgerLite.Category(name: name, iconName: "circle", colorHex: "#FFFFFF", sortOrder: index)
    }
}

// MARK: - Tests

@Suite("LogExpenseIntent — category resolution")
struct IntentCategoryResolutionTests {

    @Test("named category matches case-insensitively")
    @MainActor
    func namedMatch() {
        let all = makeCategories(["Food", "Transport", "Other"])
        let resolved = LogExpenseIntent.resolveCategory(named: "food", from: all)
        #expect(resolved?.name == "Food")
    }

    @Test("unknown name falls back to Other")
    @MainActor
    func unknownNameFallsBack() {
        let all = makeCategories(["Food", "Transport", "Other"])
        let resolved = LogExpenseIntent.resolveCategory(named: "Yachts", from: all)
        #expect(resolved?.name == "Other")
    }

    /// "Hey Siri, log $15 in LedgerLite" without naming a category must still land in
    /// "Other" — the spoken confirmation already claims it did, and an uncategorized
    /// expense is invisible to every category-based total.
    @Test("nil name falls back to Other, matching the spoken confirmation")
    @MainActor
    func nilNameFallsBack() {
        let all = makeCategories(["Food", "Transport", "Other"])
        let resolved = LogExpenseIntent.resolveCategory(named: nil, from: all)
        #expect(resolved?.name == "Other")
    }

    @Test("empty category list resolves to nil without crashing")
    @MainActor
    func emptyListIsNil() {
        let resolved = LogExpenseIntent.resolveCategory(named: nil, from: [])
        #expect(resolved == nil)
    }
}
