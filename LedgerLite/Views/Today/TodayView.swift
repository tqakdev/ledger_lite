import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: TodayViewModel?
    @State private var forecastVM: ForecastViewModel?
    @State private var showRunwayDetail = false
    @State private var showRunwaySetup  = false
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
            if forecastVM == nil {
                forecastVM = ForecastViewModel(context: modelContext)
            }
            viewModel?.refresh()
            forecastVM?.refresh()
        }
        .sheet(item: sheetBinding) { sheet in
            ExpenseFormSheet(mode: sheet.formMode, autoScan: sheet.startsWithScan) {
                viewModel?.dismissSheet()
                forecastVM?.refresh()
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LedgerLitePresentScan"))) { _ in
            viewModel?.presentScan()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func todayContent(_ viewModel: TodayViewModel) -> some View {
        List {
            Section {
                runwayCard()
                    .padding(.horizontal, 12)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                todaySummaryCard(viewModel)
                    .padding(.horizontal, 12)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section(String(localized: "Expenses")) {
                if viewModel.expenses.isEmpty {
                    emptyExpensesRow
                } else {
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
            }
            Section { Color.clear.frame(height: 80) }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .refreshable {
            viewModel.refresh()
            forecastVM?.refresh()
        }
    }

    // MARK: - Runway card

    @ViewBuilder
    private func runwayCard() -> some View {
        if let fvm = forecastVM {
            RunwayCardView(
                result: fvm.result,
                hasSetup: fvm.hasSetup,
                currencyCode: fvm.homeCurrencyCode,
                onOpenDetail: { showRunwayDetail = true },
                onSetup: { showRunwaySetup = true }
            )
            .sheet(isPresented: $showRunwayDetail) {
                if let result = fvm.result {
                    RunwayDetailView(result: result, currencyCode: fvm.homeCurrencyCode) {
                        showRunwayDetail = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showRunwaySetup = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showRunwaySetup) {
                RunwaySetupSheet(
                    currencyCode: fvm.homeCurrencyCode,
                    isConfigured: fvm.hasSetup,
                    initialBalanceMinor: UserPreferences.availableBalanceMinor,
                    initialPayday: UserPreferences.nextPayday,
                    onSave: { balance, payday in fvm.saveSetup(balanceMinor: balance, payday: payday) },
                    onClear: { fvm.clearSetup() }
                )
            }
        }
    }

    private var emptyExpensesRow: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text(String(localized: "No expenses today"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Tap + to log your first expense."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 16)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Summary card

    private func todaySummaryCard(_ viewModel: TodayViewModel) -> some View {
        SummaryCard(
            title: String(localized: "Today's Total"),
            money: Money(minorUnits: viewModel.todayTotalMinor, currencyCode: viewModel.homeCurrencyCode),
            subtitle: Date.now.formatted(date: .complete, time: .omitted)
        ) {
            HStack(spacing: 6) {
                velocityLabel(viewModel)
                streakChip(viewModel)
            }
            safeToSpendChip(viewModel)
        }
        .redacted(reason: viewModel.isLoading && viewModel.expenses.isEmpty ? .placeholder : [])
        // Deferred metrics fade in once computed rather than snapping into place.
        .animation(.easeInOut(duration: 0.25), value: viewModel.dailyAverageMinor)
        .animation(.easeInOut(duration: 0.25), value: viewModel.currentStreak)
        .animation(.easeInOut(duration: 0.25), value: viewModel.safeToSpendMinor)
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
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
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
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    @ViewBuilder
    private func safeToSpendChip(_ viewModel: TodayViewModel) -> some View {
        if let safe = viewModel.safeToSpendMinor {
            let overBudget = safe <= 0
            HStack(spacing: 4) {
                Image(systemName: overBudget ? "exclamationmark.shield.fill" : "shield.checkmark.fill")
                    .font(.caption)
                if overBudget {
                    Text(String(localized: "Budget exceeded"))
                        .font(.caption)
                } else {
                    Text(String(localized: "Safe to spend: \(Money(minorUnits: safe, currencyCode: viewModel.homeCurrencyCode).formatted()) today"))
                        .font(.caption)
                }
            }
            .foregroundStyle(overBudget ? .red : Color.mint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((overBudget ? Color.red : Color.mint).opacity(0.12))
            .clipShape(Capsule())
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    // MARK: - FAB

    private func quickAddFAB(_ viewModel: TodayViewModel) -> some View {
        VStack(alignment: .trailing, spacing: 14) {
            scanButton(viewModel)
            FABView(isVisible: $fabVisible, isSheetOpen: viewModel.activeSheet != nil) {
                viewModel.presentQuickAdd()
            }
        }
    }

    private func scanButton(_ viewModel: TodayViewModel) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.presentScan()
        } label: {
            Image(systemName: "doc.text.viewfinder")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.accentColor.opacity(0.25), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
        }
        .padding(.trailing, 26)
        .accessibilityLabel(String(localized: "Scan receipt"))
        .scaleEffect(fabVisible ? 1.0 : 0.01)
        .animation(.spring(duration: 0.4, bounce: 0.4), value: fabVisible)
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
