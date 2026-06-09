import SwiftUI
import VisionKit
import PhotosUI

/// Entry point for scanning a receipt: take a photo with the document camera or
/// pick an existing image, OCR it on-device, parse it, and hand back a
/// `ParsedReceipt`. Owns no persistence — the caller applies the result.
struct ReceiptScanView: View {
    let defaultCurrency: String
    let onComplete: (ParsedReceipt) -> Void
    let onCancel: () -> Void

    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var processing = false
    @State private var errorText: String?

    private let scanner = ReceiptScanner()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                if processing {
                    ProgressView { Text(String(localized: "Reading receipt…")) }
                        .controlSize(.large)
                } else {
                    chooser
                }
                Spacer()
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding()
            .navigationTitle(String(localized: "Scan Receipt"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { onCancel() }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                DocumentCameraView { images in
                    showCamera = false
                    if let first = images.first { process(first) }
                } onCancel: {
                    showCamera = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await loadPickedPhoto(item) }
            }
        }
    }

    // MARK: - Chooser

    private var chooser: some View {
        VStack(spacing: 16) {
            IconTile(systemName: "doc.text.viewfinder", color: Theme.brand, size: 96)
            Text(String(localized: "Scan a receipt"))
                .font(.system(.title2, design: .rounded, weight: .semibold))
            Text(String(localized: "Snap a photo or pick one from your library. Everything is read on your device — nothing is uploaded."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if VNDocumentCameraViewController.isSupported {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showCamera = true
                } label: {
                    Label(String(localized: "Take Photo"), systemImage: "camera.fill")
                }
                .buttonStyle(BrandButtonStyle())
            }

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(String(localized: "Choose Photo"), systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Processing

    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data)
        else {
            errorText = String(localized: "Couldn't load that image.")
            return
        }
        process(image)
    }

    private func process(_ image: UIImage) {
        guard let cgImage = image.cgImage else {
            errorText = String(localized: "Couldn't read that image.")
            return
        }
        processing = true
        errorText = nil
        Task {
            do {
                let text = try await scanner.recognizeText(in: cgImage)
                let receipt = ReceiptTextParser.parse(text, defaultCurrency: defaultCurrency)
                processing = false
                onComplete(receipt)
            } catch {
                processing = false
                errorText = String(localized: "Couldn't read the receipt. Try again or enter it manually.")
                AppLogger.ui.error("Receipt OCR failed: \(error)")
            }
        }
    }
}

// MARK: - Document camera

/// Wraps `VNDocumentCameraViewController` (auto edge-detection, perspective
/// correction). v1 uses the first scanned page.
private struct DocumentCameraView: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let parent: DocumentCameraView
        init(_ parent: DocumentCameraView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onScan(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            AppLogger.ui.error("Document camera failed: \(error)")
            parent.onCancel()
        }
    }
}
