import SwiftUI
import SwiftData

// A7: shimmer animation modifier used on the empty-state icon
private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .white.opacity(0.7), location: 0.5),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: UnitPoint(x: phase, y: 0.5),
                    endPoint:   UnitPoint(x: phase + 1, y: 0.5)
                )
                .blendMode(.sourceAtop)
            }
            .onAppear {
                phase = -1
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

private extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: TodayViewModel?
    // C3: error alert state
    @State private var showError  = false
    @State private var errorText  = ""

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    todayContent(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(String(localized: "Today"))
            .navigationBarTitleDisplayMode(.large)  // A9
        }
        .overlay(alignment: .bottomTrailing) {
            if let viewModel {
                quickAddFAB(viewModel)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = TodayViewModel(context: modelContext)
            }
            viewModel?.refresh()
        }
        .sheet(item: sheetBinding) { sheet in
            ExpenseFormSheet(mode: sheet.formMode) {
                viewModel?.dismissSheet()
            }
        }
        // C3: error alert
        .alert(String(localized: "Something went wrong"), isPresented: $showError) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorText)
        }
        .onChange(of: viewModel?.errorMessage) { _, msg in
            if let msg {
                errorText = msg
                showError = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)  // C1 error haptic
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func todayContent(_ viewModel: TodayViewModel) -> some View {
        if viewModel.expenses.isEmpty && !viewModel.isLoading {
            emptyState
        } else {
            VStack(spacing: 0) {
                // A5: card above the list so it has no separator line artefact
                todaySummaryCard(viewModel)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                List {
                    Section(String(localized: "Expenses")) {
                        ForEach(viewModel.expenses, id: \.id) { expense in
                            ExpenseRowView(
                                expense: expense,
                                homeCurrencyCode: viewModel.homeCurrencyCode
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.presentEdit(for: expense)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()  // C1
                                    viewModel.deleteExpense(expense)
                                } label: {
                                    Label(String(localized: "Delete"), systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    viewModel.presentEdit(for: expense)
                                } label: {
                                    Label(String(localized: "Edit"), systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Summary card (A5)

    private func todaySummaryCard(_ viewModel: TodayViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Today's Total"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(viewModel.todayTotalFormatted)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
            // A5: velocity indicator — only shown when 30-day history exists
            velocityLabel(viewModel)
            Text(Date.now.formatted(date: .complete, time: .omitted))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        // C4: placeholder skeleton on initial load before any expenses are fetched
        .redacted(reason: viewModel.isLoading && viewModel.expenses.isEmpty ? .placeholder : [])
    }

    @ViewBuilder
    private func velocityLabel(_ viewModel: TodayViewModel) -> some View {
        if viewModel.dailyAverageMinor > 0 {
            let isAbove = viewModel.todayTotalMinor > viewModel.dailyAverageMinor
            Text(isAbove
                 ? String(localized: "↑ above avg")
                 : String(localized: "↓ below avg"))
                .font(.caption)
                .foregroundStyle(isAbove ? .orange : .green)
        }
    }

    // MARK: - FAB

    private func quickAddFAB(_ viewModel: TodayViewModel) -> some View {
        Button {
            viewModel.presentQuickAdd()
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .accessibilityLabel(String(localized: "Quick Add"))
    }

    // MARK: - Empty state (A7)

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .shimmer()  // A7: repeating shimmer over the icon
            VStack(spacing: 8) {
                Text(String(localized: "No Expenses Today"))
                    .font(.title2.bold())
                Text(String(localized: "Your first expense takes 3 seconds."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button(String(localized: "Quick Add")) {
                viewModel?.presentQuickAdd()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    // MARK: - Helpers

    private var sheetBinding: Binding<TodaySheet?> {
        Binding(
            get: { viewModel?.activeSheet },
            set: { viewModel?.activeSheet = $0 }
        )
    }
}

#if DEBUG
#Preview {
    TodayView()
        .modelContainer(PreviewContainer.shared)
}
#endif
