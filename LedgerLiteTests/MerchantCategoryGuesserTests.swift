import Testing
@testable import LedgerLite

@Suite("MerchantCategoryGuesser")
struct MerchantCategoryGuesserTests {

    private let available: Set<String> = [
        "Food", "Transport", "Groceries", "Bills", "Entertainment",
        "Health", "Shopping", "Travel", "Subscriptions", "Other",
    ]

    @Test("history match wins over keywords")
    func historyWins() {
        // "Pret" would keyword-match Food, but history says the user files it under Shopping.
        let history = [(merchant: "Pret A Manger", categoryName: "Shopping")]
        let guess = MerchantCategoryGuesser.guess(merchant: "Pret A Manger", history: history, available: available)
        #expect(guess == "Shopping")
    }

    @Test("history match ignored when category no longer exists")
    func historyStaleCategory() {
        let history = [(merchant: "Pret", categoryName: "Brunch")]   // not in available
        let guess = MerchantCategoryGuesser.guess(merchant: "Pret", history: history, available: available)
        #expect(guess == "Food")   // falls back to keyword
    }

    @Test("keyword fallback: coffee shop → Food")
    func keywordFood() {
        #expect(MerchantCategoryGuesser.guess(merchant: "Joe's Coffee", history: [], available: available) == "Food")
    }

    @Test("keyword fallback: supermarket → Groceries")
    func keywordGroceries() {
        #expect(MerchantCategoryGuesser.guess(merchant: "Tesco Supermarket", history: [], available: available) == "Groceries")
    }

    @Test("keyword fallback: NIKE STORE → Shopping")
    func keywordShoppingNike() {
        #expect(MerchantCategoryGuesser.guess(merchant: "NIKE STORE", history: [], available: available) == "Shopping")
    }

    @Test("no match → nil")
    func noMatch() {
        #expect(MerchantCategoryGuesser.guess(merchant: "Zxqv Holdings", history: [], available: available) == nil)
    }

    @Test("empty merchant → nil")
    func emptyMerchant() {
        #expect(MerchantCategoryGuesser.guess(merchant: "", history: [], available: available) == nil)
    }
}
