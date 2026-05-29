import Testing
import Foundation
@testable import LedgerLite

@Suite("ReceiptTextParser — number normalization")
struct ReceiptParserNumberTests {

    @Test("US grouping: 1,234.56 → 1234.56")
    func usGrouping() {
        #expect(ReceiptTextParser.parseDecimal("1,234.56") == Decimal(string: "1234.56"))
    }

    @Test("EU grouping: 1.234,56 → 1234.56")
    func euGrouping() {
        #expect(ReceiptTextParser.parseDecimal("1.234,56") == Decimal(string: "1234.56"))
    }

    @Test("Decimal comma: 12,50 → 12.50")
    func decimalComma() {
        #expect(ReceiptTextParser.parseDecimal("12,50") == Decimal(string: "12.50"))
    }

    @Test("Thousands dot: 1.234 → 1234")
    func thousandsDot() {
        #expect(ReceiptTextParser.parseDecimal("1.234") == Decimal(1234))
    }

    @Test("Plain decimal: 8.45 → 8.45")
    func plainDecimal() {
        #expect(ReceiptTextParser.parseDecimal("8.45") == Decimal(string: "8.45"))
    }
}

@Suite("ReceiptTextParser — receipts")
struct ReceiptParserReceiptTests {

    @Test("café receipt: total, merchant, date, USD")
    func cafeReceipt() {
        let text = """
        Blue Bottle Coffee
        123 Main Street
        2024-03-15
        Latte 4.50
        Croissant 3.25
        Subtotal 7.75
        Tax 0.70
        Total $8.45
        """
        let r = ReceiptTextParser.parse(text)
        #expect(r.amountMinor == 845)
        #expect(r.amountConfident)
        #expect(r.currencyCode == "USD")
        #expect(r.merchant == "Blue Bottle Coffee")
        #expect(r.date != nil)
    }

    @Test("prefers Total over Subtotal and Tip")
    func ignoresSubtotalAndTip() {
        let text = """
        The Bistro
        Subtotal 40.00
        Tip 8.00
        Total 48.00
        """
        let r = ReceiptTextParser.parse(text, defaultCurrency: "USD")
        #expect(r.amountMinor == 4800)
        #expect(r.amountConfident)
    }

    @Test("EUR receipt with decimal comma")
    func eurReceipt() {
        let text = """
        Supermarkt Müller
        Brot 2,50
        Milch 1,20
        Summe
        Total 3,70 €
        """
        let r = ReceiptTextParser.parse(text)
        #expect(r.currencyCode == "EUR")
        #expect(r.amountMinor == 370)
        #expect(r.amountConfident)
    }

    @Test("GBP single-line total")
    func gbpReceipt() {
        let r = ReceiptTextParser.parse("Tesco\nTotal £12.99")
        #expect(r.currencyCode == "GBP")
        #expect(r.amountMinor == 1299)
    }

    @Test("no total label → low-confidence fallback to largest price")
    func fallbackLargest() {
        let text = """
        Corner Store
        3.00
        12.50
        """
        let r = ReceiptTextParser.parse(text, defaultCurrency: "USD")
        #expect(r.amountMinor == 1250)
        #expect(r.amountConfident == false)
    }

    @Test("empty-ish receipt yields no amount")
    func noAmount() {
        let r = ReceiptTextParser.parse("Hello\nThank you")
        #expect(r.amountMinor == nil)
        #expect(r.merchant == "Hello")
    }

    @Test("store name containing 'Store' is not mistaken for noise; address is skipped")
    func storeNameNotRejected() {
        let text = """
        NIKE STORE
        2100 Southcenter Mall
        Tukwila, WA 98188
        (206) 555-7716
        03/03/2026 6:18:42 PM
        Air Jordan 4 x1 $489.00
        Subtotal $563.99
        Sales tax $47.11
        Total $611.10
        """
        let r = ReceiptTextParser.parse(text)
        #expect(r.merchant == "NIKE STORE")
        #expect(r.amountMinor == 61110)
        #expect(r.currencyCode == "USD")
    }

    @Test("merchant line starting with a number (address) is skipped")
    func addressLineSkipped() {
        let r = ReceiptTextParser.parse("123 Market Street\nCoffee House\nTotal $5.00")
        #expect(r.merchant == "Coffee House")
    }

    @Test("line items are extracted, excluding subtotal/tax/total")
    func lineItems() {
        let text = """
        NIKE STORE
        2100 Southcenter Mall
        Air Jordan 4 (Men's) x1 $489.00
        Premium sneaker cleaner x1 $32.99
        Crew socks (2-pack) x2 $28.00
        Lace set (extra) x1 $14.00
        Subtotal $563.99
        Sales tax $47.11
        Total $611.10
        """
        let r = ReceiptTextParser.parse(text)
        #expect(r.lineItems.count == 4)
        #expect(r.lineItems.first?.name == "Air Jordan 4 (Men's) x1")
        #expect(r.lineItems.first?.amountMinor == 48900)
        #expect(r.lineItems.last?.amountMinor == 1400)
        // No subtotal/tax/total leaking in as items.
        #expect(r.lineItems.allSatisfy { !$0.name.lowercased().contains("total") })
        #expect(r.lineItems.allSatisfy { $0.amountMinor != 61110 })
    }

    @Test("single-line receipt with a price but no description yields no items")
    func noSpuriousItems() {
        let r = ReceiptTextParser.parse("Corner Store\nTotal $5.00")
        #expect(r.lineItems.isEmpty)
    }

    @Test("wrapped description merges into its priced line")
    func wrappedLineItem() {
        let text = """
        NIKE STORE
        Air Jordan 4 (Men's
        x1 $489.00
        10.5) denim edition
        Premium sneaker cleaner x1 $32.99
        Total $521.99
        """
        let r = ReceiptTextParser.parse(text)
        #expect(r.lineItems.count == 2)
        #expect(r.lineItems.first?.name == "Air Jordan 4 (Men's x1")
        #expect(r.lineItems.first?.amountMinor == 48900)
        #expect(r.lineItems.last?.name == "Premium sneaker cleaner x1")
        #expect(r.amountMinor == 52199)
    }

    @Test("priced line with only a quantity and no description above it is skipped")
    func quantityOnlyLineSkipped() {
        // No descriptive line precedes the quantity-only price, so there's
        // nothing to name the item — it must not produce a junk "x1" entry.
        let r = ReceiptTextParser.parse("x1 $5.00\nTotal $5.00")
        #expect(r.lineItems.isEmpty)
    }

    @Test("real Vision OCR of the Nike receipt: total + all four items")
    func realNikeOCR() {
        // Captured verbatim from Vision on the actual receipt — note the column is
        // split onto separate lines and interleaved (price-above-name, name-above-price),
        // and "10.5" (shoe size) / "1104" (card) must not be read as money.
        let text = """
        NIKE STORE
        2100 Southcenter Mall
        Tukwila, WA 98188
        (206) 555-7716
        03/03/2026 6:18:42 PM
        Receipt: NKX-904118
        Associate: J. Calder
        Purchase: In-store
        x1 $489.00
        Air Jordan 4 (Men's
        10.5) A denim edition
        Premium sneaker cleaner x1 $32.99
        kit
        Crew socks (2-pack) x2
        $28.00
        Lace set (extra) x1
        $14.00
        $563.99
        Subtotal
        $47.11
        Sales tax
        $611.10
        Total
        **** 1104
        Card number
        """
        let r = ReceiptTextParser.parse(text)
        #expect(r.merchant == "NIKE STORE")
        #expect(r.currencyCode == "USD")
        #expect(r.amountMinor == 61110)
        #expect(r.amountConfident)

        #expect(r.lineItems.count == 4)
        #expect(r.lineItems.map(\.amountMinor) == [48900, 3299, 2800, 1400])
        #expect(r.lineItems[0].name.contains("Air Jordan 4"))
        #expect(r.lineItems[1].name.contains("Premium sneaker cleaner"))
        #expect(r.lineItems[2].name.contains("Crew socks"))
        #expect(r.lineItems[3].name.contains("Lace set"))
    }

    @Test("zero-decimal currency (JPY) scales without fraction")
    func jpyZeroDecimals() {
        let text = """
        ラーメン店
        Total ¥1500
        """
        let r = ReceiptTextParser.parse(text)
        #expect(r.currencyCode == "JPY")
        #expect(r.amountMinor == 1500)
    }
}
