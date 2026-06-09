import SwiftUI
import SwiftData

/// The app's home screen and identity: a forward-looking payday runway. The forecast
/// is the centerpiece — today's spending is supporting context, and the full expense
/// log lives in the Spending tab. This is what re-centers the app away from being a
/// backward-looking ledger.
struct RunwayView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: TodayViewModel?
    @State private var forecastVM: ForecastViewModel?
    @State private var fabVisible = false
    @State private var showRunwaySetup = false
    @State private var showError = false
    @State private var errorText = ""

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel, let forecastVM {
                    content(viewModel, forecastVM)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(String(localized: "Runway"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let forecastVM, forecastVM.hasSetup {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showRunwaySetup = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .accessibilityLabel(String(localized: "Edit runway"))
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let viewModel {
                ExpenseFABCluster(
                    isVisible: $fabVisible,
                    isSheetOpen: viewModel.activeSheet != nil,
                    onAdd: { viewModel.presentQuickAdd() },
                    onScan: { viewModel.presentScan() }
                )
            }
        }
        .onAppear {
            if viewModel == nil { viewModel = TodayViewModel(context: modelContext) }
            if forecastVM == nil { forecastVM = ForecastViewModel(context: modelContext) }
            viewModel?.refresh()
            forecastVM?.refresh()
        }
        .sheet(item: sheetBinding) { sheet in
            ExpenseFormSheet(mode: sheet.formMode, autoScan: sheet.startsWithScan) {
                viewModel?.dismissSheet()
                forecastVM?.refresh()
            }
        }
        .sheet(isPresented: $showRunwaySetup) {
            if let forecastVM {
                RunwaySetupSheet(
                    currencyCode: forecastVM.homeCurrencyCode,
                    isConfigured: forecastVM.hasSetup,
                    initialBalanceMinor: UserPreferences.availableBalanceMinor,
                    initialPayday: UserPreferences.nextPayday,
                    onSave: { balance, payday in forecastVM.saveSetup(balanceMinor: balance, payday: payday) },
                    onClear: { forecastVM.clearSetup() }
                )
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
    private func content(_ viewModel: TodayViewModel, _ forecastVM: ForecastViewModel) -> some View {
        List {
            Section {
                runwayHero(viewModel, forecastVM)
                    .padding(.horizontal, 12)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section(String(localized: "Today")) {
                todaySummaryCard(viewModel)
                    .padding(.horizontal, 12)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section { Color.clear.frame(height: 80) }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .refreshable {
            viewModel.refresh()
            forecastVM.refresh()
        }
    }

    // MARK: - Runway hero

    @ViewBuilder
    private func runwayHero(_ viewModel: TodayViewModel, _ forecastVM: ForecastViewModel) -> some View {
        if forecastVM.hasSetup, let result = forecastVM.result {
            RunwayForecastView(
                result: result,
                currencyCode: forecastVM.homeCurrencyCode,
                lastInput: forecastVM.lastInput,
                todayTotalMinor: viewModel.todayTotalMinor
            )
        } else {
            RunwaySetupPromptView { showRunwaySetup = true }
        }
    }

    // MARK: - Today summary

    private func todaySummaryCard(_ viewModel: TodayViewModel) -> some View {
        SummaryCard(
            title: String(localized: "Spent Today"),
            money: Money(minorUnits: viewModel.todayTotalMinor, currencyCode: viewModel.homeCurrencyCode),
            subtitle: Date.now.formatted(date: .complete, time: .omitted)
        ) {
            HStack(spacing: 6) {
                velocityLabel(viewModel)
                streakChip(viewModel)
            }
        }
        .redacted(reason: viewModel.isLoading && viewModel.expenses.isEmpty ? .placeholder : [])
        .animation(.easeInOut(duration: 0.25), value: viewModel.dailyAverageMinor)
        .animation(.easeInOut(duration: 0.25), value: viewModel.currentStreak)
    }

    @ViewBuilder
    private func velocityLabel(_ viewModel: TodayViewModel) -> some View {
        if viewModel.dailyAverageMinor > 0 {
            let isAbove = viewModel.todayTotalMinor > viewModel.dailyAverageMinor
            HStack(spacing: 4) {
                Image(systemName: isAbove ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                Text(isAbove
                     ? String(localized: "above avg")
                     : String(localized: "below avg"))
            }
            .chip(isAbove ? Theme.caution : Theme.positive)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    @ViewBuilder
    private func streakChip(_ viewModel: TodayViewModel) -> some View {
        if viewModel.currentStreak >= 2 {
            HStack(spacing: 4) {
                Text("🔥")
                Text(String(localized: "\(viewModel.currentStreak)-day streak"))
            }
            .chip(Theme.caution)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
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
    RunwayView()
        .modelContainer(PreviewContainer.shared)
}
#endif
