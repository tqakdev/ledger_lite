import Foundation
import Vision
import CoreGraphics

enum ReceiptScannerError: Error {
    case recognitionFailed
}

/// Thin wrapper around Vision's on-device text recognition. This is the
/// untestable boundary (no real images in unit tests); all parsing logic lives
/// in `ReceiptTextParser`, which this feeds.
struct ReceiptScanner {

    /// Recognizes text in an image and returns it as newline-separated lines in
    /// top-to-bottom reading order. Runs off the main thread.
    func recognizeText(in cgImage: CGImage) async throws -> String {
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
                    // Vision's origin is bottom-left, so a larger maxY sits higher on the page.
                    let ordered = observations.sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
                    let lines = ordered.compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: lines.joined(separator: "\n"))
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

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
