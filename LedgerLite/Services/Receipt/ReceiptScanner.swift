import Foundation
import Vision
import CoreGraphics

enum ReceiptScannerError: Error {
    case recognitionFailed
}

/// Thin wrapper around Vision's on-device text recognition. This is the
/// untestable boundary (no real images in unit tests); the row reconstruction
/// (`ReceiptLineGrouper`) and field parsing (`ReceiptTextParser`) it feeds are
/// both pure and tested.
struct ReceiptScanner {

    /// Recognizes text and returns it as newline-separated **visual rows** —
    /// reconstructed from observation geometry, not Vision's reading order, so a
    /// description and its price column end up on the same line. Runs off the
    /// main thread.
    func recognizeText(in cgImage: CGImage) async throws -> String {
        let words = try await recognizeWords(in: cgImage)
        return ReceiptLineGrouper.rows(from: words).joined(separator: "\n")
    }

    private func recognizeWords(in cgImage: CGImage) async throws -> [OCRWord] {
        try await withCheckedThrowingContinuation { continuation in
            // Build the request inside the background block so no non-Sendable
            // Vision object is captured across the concurrency boundary.
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                    let words = observations.compactMap { observation -> OCRWord? in
                        guard let text = observation.topCandidates(1).first?.string else { return nil }
                        return OCRWord(text: text, frame: observation.boundingBox)
                    }
                    continuation.resume(returning: words)
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                // Receipts are frequently non-English; let Vision pick the
                // script instead of assuming the device language.
                request.automaticallyDetectsLanguage = true

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
