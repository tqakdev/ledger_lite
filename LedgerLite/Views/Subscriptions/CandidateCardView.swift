import SwiftUI

struct CandidateCardView: View {
    let candidate: SubscriptionCandidate
    let viewModel: AutoDetectViewModel

    @State private var selectedCategory: Category?
    @State private var isConfirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            Text(candidate.billingCycle.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            if candidate.isDuplicate {
                duplicateBadge
            } else {
                CategoryPickerStrip(
                    categories: viewModel.categories,
                    selected: $selectedCategory
                )
                if candidate.confidenceTier == .dim {
                    Text(String(localized: "Low confidence"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            actionRow
        }
        .padding(.vertical, 4)
        .opacity(candidate.confidenceTier == .dim ? 0.55 : 1.0)
        .onAppear {
            selectedCategory = viewModel.categories.first(where: { $0.name == "Other" })
                ?? viewModel.categories.first
        }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if candidate.confidenceTier == .strong {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Text(candidate.name)
                        .font(.headline)
                        .foregroundStyle(candidate.isDuplicate ? .secondary : .primary)
                }
                Text(candidate.money.formatted())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(candidate.confidence * 100))%")
                .font(.caption2)
                .foregroundStyle(candidate.confidenceTier == .dim ? .tertiary : .secondary)
                .monospacedDigit()
        }
    }

    private var duplicateBadge: some View {
        Text(String(localized: "Already tracked"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.secondary.opacity(0.12))
            .clipShape(Capsule())
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(String(localized: "Dismiss")) {
                viewModel.dismiss(candidate)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                isConfirming = true
                Task {
                    await viewModel.confirm(candidate, category: selectedCategory)
                    isConfirming = false
                }
            } label: {
                if isConfirming {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(String(localized: "Confirm"))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(candidate.isDuplicate || isConfirming)
        }
    }
}
