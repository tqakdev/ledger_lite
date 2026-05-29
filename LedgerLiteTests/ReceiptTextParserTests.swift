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
