import SwiftUI

struct CandidateCardView: View {
    let candidate: SubscriptionCandidate
    let viewModel: AutoDetectViewModel

    @State private var selectedCategory: Category?
    @State private var isConfirming = false
    @State private var nextBillingDate: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            HStack(spacing: 6) {
                Text(candidate.billingCycle.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("\(Int(candidate.confidence * 100))%")
                    .font(.caption2)
                    .foregroundStyle(candidate.confidenceTier == .dim ? .tertiary : .secondary)
                    .monospacedDigit()
            }

            if candidate.isDuplicate {
                duplicateBadge
            } else {
                DatePicker(
                    String(localized: "Next billing"),
                    selection: $nextBillingDate,
                    displayedComponents: .date
                )
                .font(.caption)
                .datePickerStyle(.compact)

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
            nextBillingDate = candidate.detectedNextBillingDate
                ?? candidate.billingCycle.nextDate(after: Date.utcToday)
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
                    await viewModel.confirm(candidate, category: selectedCategory, nextBillingDate: nextBillingDate)
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
