import SwiftUI
import SwiftData

struct AutoDetectSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: AutoDetectViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    if viewModel.candidates.isEmpty {
                        pasteZone(viewModel)
                    } else {
                        candidateList(viewModel)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(String(localized: "Scan for Subscriptions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) { dismiss() }
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                let vm = AutoDetectViewModel(context: modelContext)
                vm.loadCategories()
                viewModel = vm
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Phase A: paste zone

    private func pasteZone(_ viewModel: AutoDetectViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "Paste email, SMS, or receipt text here"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ZStack(alignment: .topLeading) {
                    if viewModel.rawText.isEmpty {
                        Text(String(localized: "e.g. Your Netflix subscription renews on Jan 15 for $15.49…"))
                            .foregroundStyle(.tertiary)
                            .font(.body)
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: rawTextBinding(viewModel))
                        .frame(minHeight: 200)
                        .scrollContentBackground(.hidden)
                }
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack {
                    Button(String(localized: "Paste from Clipboard")) {
                        if let text = UIPasteboard.general.string {
                            viewModel.rawText = text
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(String(localized: "Scan")) {
                        viewModel.runDetection()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
    }

    // MARK: - Phase B: candidate review

    private func candidateList(_ viewModel: AutoDetectViewModel) -> some View {
        List {
            Section {
                ForEach(viewModel.candidates) { candidate in
                    CandidateCardView(candidate: candidate, viewModel: viewModel)
                }
            } header: {
                Text(candidateHeader(viewModel.candidates.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(String(localized: "Confirm All")) {
                    Task { await viewModel.confirmAll() }
                }
                .disabled(viewModel.candidates.allSatisfy { $0.isDuplicate } || viewModel.isSaving)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button(String(localized: "Start Over")) {
                    viewModel.candidates = []
                    viewModel.rawText = ""
                    viewModel.errorMessage = nil
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Close")) { dismiss() }
            }
        }
        .onChange(of: viewModel.candidates) { _, newValue in
            if newValue.isEmpty && viewModel.hasConfirmedAtLeastOne { dismiss() }
        }
    }

    // MARK: - Helpers

    private func candidateHeader(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 subscription found")
            : String(localized: "\(count) subscriptions found")
    }

    private func rawTextBinding(_ viewModel: AutoDetectViewModel) -> Binding<String> {
        Binding(
            get: { viewModel.rawText },
            set: { viewModel.rawText = $0 }
        )
    }
}
