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

    @Test("a bare amount row with no description is not an item")
    func quantityOnlyLineSkipped() {
        // Rejoining wrapped descriptions is ReceiptLineGrouper's job; the parser
        // only reads clean rows, so a row that's just a quantity+price is skipped.
        let r = ReceiptTextParser.parse("x1 $5.00\nTotal $5.00")
        #expect(r.lineItems.isEmpty)
    }

    @Test("Nike receipt (geometry-reconstructed rows): total + all four items")
    func realNikeOCR() {
        // These are the rows ReceiptLineGrouper produces from the real Vision output —
        // description and price column rejoined. "10.5" (size) / "1104" (card) are
        // not money; subtotal/tax/total/card rows are excluded.
        let text = """
        NIKE STORE
        2100 Southcenter Mall
        Tukwila, WA 98188
        (206) 555-7716
        03/03/2026 6:18:42 PM
        Receipt: NKX-904118
        Associate: J. Calder
        Purchase: In-store
        Air Jordan 4 (Men's x1 $489.00
        10.5) A denim edition
        Premium sneaker cleaner x1 $32.99
        kit
        Crew socks (2-pack) x2 $28.00
        Lace set (extra) x1 $14.00
        Subtotal $563.99
        Sales tax $47.11
        Total $611.10
        Card number **** 1104
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

    @Test("Lidl receipt (geometry rows): groceries kept, payment/tax/unit-price dropped")
    func realLidlOCR() {
        // Geometry-reconstructed rows from the real Vision output of a Portuguese
        // Lidl receipt (decimal comma, no currency symbol, pt-PT payment terms).
        let text = """
        LODL
        V. REAL STO ANTONIO
        Contribuinte Nr. 503 340 855
        EUR
        TOMATE DE CACHO 0,80 B
        0,540 kg x 1,49 EUR/kg
        ABACAXI 1,33 B
        1,345 kg x 0,99 EUR/kg
        BATATA CONS. ROXA BX 2,37 B
        AMEIXA RAIN. CLA.EMB. 1,99 B
        MOZZARELLA SORT. 0,89 B
        QUEIJO CABRA 1,99 B
        QUEIJO FETA 1,79 B
        AZEITE GALLO 1º 2,49 B
        CORNICHONS 1,99 C
        BRANCO REG RIBATEJO 2,58 C
        2 x 1,29
        AGUA DE NASCENTE 1,74 B
        Total 19,96
        DINHEIRO 20,00
        TROCO -0,04
        B 6% 14,52 15,39 0,87
        """
        let r = ReceiptTextParser.parse(text, defaultCurrency: "EUR")
        #expect(r.currencyCode == "EUR")
        #expect(r.amountMinor == 1996)
        #expect(r.amountConfident)

        #expect(r.lineItems.count == 11)
        #expect(r.lineItems.first?.name == "TOMATE DE CACHO")
        #expect(r.lineItems.first?.amountMinor == 80)
        #expect(r.lineItems.contains { $0.name == "AZEITE GALLO 1º" && $0.amountMinor == 249 })
        // Payment / tax / unit-price rows must not appear as items.
        #expect(r.lineItems.allSatisfy { !$0.name.lowercased().contains("dinheiro") })
        #expect(r.lineItems.allSatisfy { !$0.name.lowercased().contains("troco") })
        #expect(r.lineItems.allSatisfy { !$0.name.lowercased().contains("kg") })
        #expect(r.lineItems.allSatisfy { $0.amountMinor != 2000 && $0.amountMinor != 1996 })
    }

    @Test("Morrisons receipt: drops the promotion/discount line, keeps real items")
    func realMorrisonsOCR() {
        // Geometry rows from the real Vision OCR of a UK Morrisons receipt — has a
        // promotions section with a negative discount that must not become an item.
        let text = """
        Morrisons Daily
        Bristol BS16 1QY
        KINDER BUENO TWIN FINGER BAR 4 1 1.25
        EXPRESS CUISINE CHICKEN TIKKA 1 3.10
        EXPRESS CUISINE CHICKEN TANDOO 1 3.10
        VITHIT PERFORM 500ML 500ML 1 2.10
        Total Items) Sold 9.55
        Less Promotion Discount -2.20
        Total To Pay £7.35
        EXPRESS MEAL DEAL @ £4.25 -2.20
        """
        let r = ReceiptTextParser.parse(text, defaultCurrency: "EUR")
        #expect(r.currencyCode == "GBP")          // £ detected, not the EUR default
        #expect(r.amountMinor == 735)             // "Total To Pay" beats "Total Items Sold"
        #expect(r.lineItems.count == 4)
        #expect(r.lineItems.map(\.amountMinor) == [125, 310, 310, 210])
        // The −2.20 promotion line must not appear as an item.
        #expect(r.lineItems.allSatisfy { $0.amountMinor != 220 })
        #expect(r.lineItems.allSatisfy { !$0.name.contains("MEAL DEAL") })
    }

    @Test("reconciliation: foreign receipt with no English keywords")
    func reconcilesForeignReceipt() {
        // German terms (Summe/Bar/Rückgeld) are in no keyword list — items are
        // still terminated correctly because they sum to "Summe", and that sum
        // becomes the total since there's no recognizable total label.
        let text = """
        Kaufland
        Brot 1,99 €
        Milch 0,89 €
        Käse 3,50 €
        Summe 6,38 €
        Bar 10,00 €
        Rückgeld 3,62 €
        """
        let r = ReceiptTextParser.parse(text, defaultCurrency: "EUR")
        #expect(r.lineItems.map(\.amountMinor) == [199, 89, 350])
        #expect(r.amountMinor == 638)
        #expect(r.amountConfident)
        #expect(r.lineItems.allSatisfy { !["Summe", "Bar", "Rückgeld"].contains($0.name) })
    }

    @Test("degrades gracefully when the item sum doesn't reconcile")
    func degradesWhenNoReconciliation() {
        // Items don't sum to the total (e.g. a price misread / missing line) —
        // still return the item rows and take the total from its label.
        let text = """
        Shop
        Apple 1,00 €
        Banana 2,00 €
        Total 9,99 €
        """
        let r = ReceiptTextParser.parse(text, defaultCurrency: "EUR")
        #expect(r.lineItems.count == 2)
        #expect(r.amountMinor == 999)
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
