import Foundation

/// A single purchased line on a receipt: a description and its price.
struct ReceiptLineItem: Equatable {
    let name: String
    let amountMinor: Int
}

/// The structured fields extracted from a receipt's OCR text.
/// A pure value type — produced by `ReceiptTextParser`, consumed by the
/// expense form to pre-fill a new entry. Fields are optional because any one
/// of them may be absent or unreadable on a given receipt.
struct ParsedReceipt: Equatable {
    var amountMinor: Int?
    var currencyCode: String?
    var merchant: String?
    var date: Date?

    /// True when the total was found via an explicit total/amount label rather
    /// than a best-guess fallback. The form uses this to decide whether to
    /// pre-fill the amount or leave it blank and flag it for the user.
    var amountConfident: Bool

    /// Individual purchases that make up the total, in receipt order.
    /// Discounts and refunds appear here with a **negative** amount, so the
    /// breakdown always sums to the charged total.
    var lineItems: [ReceiptLineItem]

    /// Add-on sales tax, captured only when it arithmetically completes the
    /// sum (items + discounts + tax == total). Price-inclusive VAT summaries
    /// (EU receipts) never qualify, so they are never double-counted.
    var tax: ReceiptLineItem?

    /// The raw recognized text, kept for debugging/fallback display.
    var rawText: String

    init(
        amountMinor: Int? = nil,
        currencyCode: String? = nil,
        merchant: String? = nil,
        date: Date? = nil,
        amountConfident: Bool = false,
        lineItems: [ReceiptLineItem] = [],
        tax: ReceiptLineItem? = nil,
        rawText: String = ""
    ) {
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.merchant = merchant
        self.date = date
        self.amountConfident = amountConfident
        self.lineItems = lineItems
        self.tax = tax
        self.rawText = rawText
    }

    /// Nothing useful was extracted.
    var isEmpty: Bool {
        amountMinor == nil && merchant == nil && date == nil
    }
}
