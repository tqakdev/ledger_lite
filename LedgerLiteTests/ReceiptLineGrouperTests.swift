import Testing
import Foundation
import CoreGraphics
@testable import LedgerLite

@Suite("ReceiptLineGrouper")
struct ReceiptLineGrouperTests {

    // Vision frames are normalized with origin bottom-left.
    private func word(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat = 0.2, h: CGFloat = 0.02) -> OCRWord {
        OCRWord(text: text, frame: CGRect(x: x, y: y, width: w, height: h))
    }

    @Test("two observations on the same row are joined left-to-right")
    func joinsSameRow() {
        // Description on the left, price column on the right — same vertical band.
        let words = [
            word("x1 $489.00", x: 0.70, y: 0.890),
            word("Air Jordan 4 (Men's", x: 0.10, y: 0.892),
        ]
        let rows = ReceiptLineGrouper.rows(from: words)
        #expect(rows == ["Air Jordan 4 (Men's x1 $489.00"])
    }

    @Test("observations on different rows stay separate, ordered top-to-bottom")
    func separatesRows() {
        let words = [
            word("Total", x: 0.10, y: 0.40),
            word("$611.10", x: 0.70, y: 0.402),
            word("NIKE STORE", x: 0.30, y: 0.95),
        ]
        let rows = ReceiptLineGrouper.rows(from: words)
        #expect(rows == ["NIKE STORE", "Total $611.10"])
    }

    @Test("empty input yields no rows")
    func empty() {
        #expect(ReceiptLineGrouper.rows(from: []).isEmpty)
    }
}
