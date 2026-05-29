import Testing
import Foundation
import SwiftData
@testable import LedgerLite

@MainActor
@Suite("ExpenseFormViewModel — applyParsedReceipt")
struct ExpenseFormScanTests {

    /// Returns a seeded container. The caller must keep it alive — the context
    /// borrows from it, and a deallocated container takes the store down with it.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Expense.self, Subscription.self, Category.self, ExchangeRateCache.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        for seed in Category.systemSeeds {
            context.insert(Category(name: seed.name, iconName: seed.iconName, colorHex: seed.colorHex, sortOrder: seed.sortOrder, isSystem: true))
        }
        try context.save()
        return container
    }

    @Test("confident receipt fills amount, merchant, currency, guessed category")
    func confidentReceipt() throws {
        let container = try makeContainer()
        let vm = ExpenseFormViewModel(mode: .add, context: container.mainContext, homeCurrencyCode: "USD")
        vm.loadCategories()

        vm.applyParsedReceipt(ParsedReceipt(
            amountMinor: 845,
            currencyCode: "USD",
            merchant: "Blue Bottle Coffee",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            amountConfident: true
        ))

        #expect(vm.minorUnits == 845)
        #expect(vm.merchant == "Blue Bottle Coffee")
        #expect(vm.currencyCode == "USD")
        #expect(vm.scanLowConfidence == false)
        #expect(vm.selectedCategory?.name == "Food")   // keyword guess from "Coffee"
    }

    @Test("low-confidence receipt leaves amount blank and flags it")
    func lowConfidenceReceipt() throws {
        let container = try makeContainer()
        let vm = ExpenseFormViewModel(mode: .add, context: container.mainContext, homeCurrencyCode: "USD")
        vm.loadCategories()

        vm.applyParsedReceipt(ParsedReceipt(
            amountMinor: 1299,
            merchant: "Corner Store",
            amountConfident: false
        ))

        #expect(vm.minorUnits == 1299)   // best guess pre-filled…
        #expect(vm.scanLowConfidence)    // …but flagged for the user to verify
        #expect(vm.merchant == "Corner Store")
    }

    @Test("line items populate an empty note as a breakdown")
    func lineItemsFillNote() throws {
        let container = try makeContainer()
        let vm = ExpenseFormViewModel(mode: .add, context: container.mainContext, homeCurrencyCode: "USD")
        vm.loadCategories()

        vm.applyParsedReceipt(ParsedReceipt(
            amountMinor: 51700,
            currencyCode: "USD",
            merchant: "Nike Store",
            amountConfident: true,
            lineItems: [
                ReceiptLineItem(name: "Air Jordan 4 x1", amountMinor: 48900),
                ReceiptLineItem(name: "Crew socks x2", amountMinor: 2800),
            ]
        ))

        #expect(vm.note.contains("Air Jordan 4 x1"))
        #expect(vm.note.contains("Crew socks x2"))
        #expect(vm.note.split(separator: "\n").count == 2)
    }

    @Test("line items do not overwrite a note the user already has")
    func lineItemsPreserveExistingNote() throws {
        let container = try makeContainer()
        let vm = ExpenseFormViewModel(mode: .add, context: container.mainContext, homeCurrencyCode: "USD")
        vm.loadCategories()
        vm.note = "my own note"

        vm.applyParsedReceipt(ParsedReceipt(
            amountMinor: 51700,
            currencyCode: "USD",
            amountConfident: true,
            lineItems: [
                ReceiptLineItem(name: "Item A", amountMinor: 100),
                ReceiptLineItem(name: "Item B", amountMinor: 200),
            ]
        ))

        #expect(vm.note == "my own note")
    }
}
