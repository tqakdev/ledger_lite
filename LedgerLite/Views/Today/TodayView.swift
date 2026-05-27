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
            List {
                Section {
                    todaySummaryCard(viewModel)
                        .padding(.horizontal, 12)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

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
            .listSectionSpacing(.compact)
            .refreshable { viewModel.refresh() }
        }
    }

    // MARK: - Summary card

    private func todaySummaryCard(_ viewModel: TodayViewModel) -> some View {
        SummaryCard(
            title: String(localized: "Today's Total"),
            amount: viewModel.todayTotalFormatted,
            amountMinor: viewModel.todayTotalMinor,
            subtitle: Date.now.formatted(date: .complete, time: .omitted)
        ) {
            velocityLabel(viewModel)
            streakChip(viewModel)
        }
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
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((isAbove ? Color.orange : Color.green).opacity(0.12))
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func streakChip(_ viewModel: TodayViewModel) -> some View {
        if viewModel.currentStreak >= 2 {
            HStack(spacing: 4) {
                Text("🔥")
                    .font(.caption)
                Text(String(localized: "\(viewModel.currentStreak)-day streak"))
                    .font(.caption)
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.12))
            .clipShape(Capsule())
        }
    }

    // MARK: - FAB

    private func quickAddFAB(_ viewModel: TodayViewModel) -> some View {
        FABView(isVisible: $fabVisible, isSheetOpen: viewModel.activeSheet != nil) {
            viewModel.presentQuickAdd()
        }
    }

    private struct FABView: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Binding var isVisible: Bool
        var isSheetOpen: Bool = false
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
                    .rotationEffect(reduceMotion ? .zero : .degrees(isSheetOpen ? 45 : 0))
                    .animation(.spring(response: 0.3), value: isSheetOpen)
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
        ContentUnavailableView {
            Label(String(localized: "No Expenses Today"), systemImage: "tray")
        } description: {
            Text(String(localized: "Tap + to log your first expense."))
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
