import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: TodayViewModel?
    @State private var fabVisible = false
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
            .navigationBarTitleDisplayMode(.large)
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
        .alert(String(localized: "Something went wrong"), isPresented: $showError) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorText)
        }
        .onChange(of: viewModel?.errorMessage) { _, msg in
            if let msg {
                errorText = msg
                showError = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
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
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
                    Section { Color.clear.frame(height: 80) }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Summary card

    private func todaySummaryCard(_ viewModel: TodayViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Today's Total"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(viewModel.todayTotalFormatted)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(viewModel.todayTotalMinor)))
                .animation(.spring(duration: 0.4, bounce: 0.3), value: viewModel.todayTotalMinor)
            velocityLabel(viewModel)
            Text(Date.now.formatted(date: .complete, time: .omitted))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), Color(.secondarySystemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .redacted(reason: viewModel.isLoading && viewModel.expenses.isEmpty ? .placeholder : [])
    }

    @ViewBuilder
    private func velocityLabel(_ viewModel: TodayViewModel) -> some View {
        if viewModel.dailyAverageMinor > 0 {
            let isAbove = viewModel.todayTotalMinor > viewModel.dailyAverageMinor
            HStack(spacing: 4) {
                Image(systemName: isAbove ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.caption)
                Text(isAbove
                     ? String(localized: "above avg")
                     : String(localized: "below avg"))
                    .font(.caption)
            }
            .foregroundStyle(isAbove ? .orange : .green)
        }
    }

    // MARK: - FAB

    private func quickAddFAB(_ viewModel: TodayViewModel) -> some View {
        FABView(isVisible: $fabVisible) {
            viewModel.presentQuickAdd()
        }
    }

    private struct FABView: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Binding var isVisible: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 10, x: 0, y: 5)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
            .accessibilityLabel(String(localized: "Add expense"))
            .scaleEffect(reduceMotion ? 1.0 : (isVisible ? 1.0 : 0.01))
            .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.4), value: isVisible)
            .onAppear { isVisible = true }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse)
            VStack(spacing: 8) {
                Text(String(localized: "No Expenses Today"))
                    .font(.title2.bold())
                Text(String(localized: "Tap  +  to log your first expense."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
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
