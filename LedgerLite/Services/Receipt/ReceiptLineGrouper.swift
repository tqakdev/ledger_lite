import Foundation
import CoreGraphics

/// A single OCR observation: its text and normalized frame (Vision convention —
/// origin bottom-left, values 0...1).
struct OCRWord: Equatable {
    let text: String
    let frame: CGRect
}

/// Rebuilds a receipt's visual rows from individual OCR observations using their
/// geometry. Vision returns text in a reading order that interleaves multi-column
/// layouts (the amount column lands on separate lines, sometimes above the
/// description, sometimes below). Grouping observations by vertical position and
/// then ordering each group left-to-right reconstructs the true
/// "DESCRIPTION … PRICE" rows, which makes downstream parsing reliable.
///
/// Pure and fully testable — no Vision dependency.
enum ReceiptLineGrouper {

    static func rows(from words: [OCRWord]) -> [String] {
        guard !words.isEmpty else { return [] }

        // Rows on a receipt are well separated vertically; a fraction of the
        // median text height is a robust threshold for "same row".
        let heights = words.map { $0.frame.height }.sorted()
        let medianHeight = heights[heights.count / 2]
        let tolerance = max(medianHeight * 0.6, 0.004)

        var rows: [[OCRWord]] = []
        for word in words.sorted(by: { $0.frame.midY > $1.frame.midY }) {
            if let index = rows.firstIndex(where: { abs($0[0].frame.midY - word.frame.midY) < tolerance }) {
                rows[index].append(word)
            } else {
                rows.append([word])
            }
        }

        return rows.map { row in
            row.sorted { $0.frame.minX < $1.frame.minX }
                .map(\.text)
                .joined(separator: " ")
        }
    }
}
