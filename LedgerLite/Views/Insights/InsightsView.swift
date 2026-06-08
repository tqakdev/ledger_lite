import SwiftUI
import Charts
import SwiftData

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: InsightsViewModel?
    @State private var selectedAngleValue: Int?
    @State private var showDrillDown = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showError = false
    @State private var errorText = ""
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // No NavigationStack here: Trends is pushed from the Spending tab, which
        // already provides one. Re-centering the app on the forecast means Trends
        // is a secondary destination, not a primary tab.
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(String(localized: "Trends"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let vm = viewModel, !vm.categoryTotals.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        shareInsightsSummary(vm)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            InsightsActivitySheet(items: shareItems)
        }
        .onAppear {
            if viewModel == nil {
                viewModel = InsightsViewModel(context: modelContext)
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
        .sheet(isPresented: $showDrillDown) {
            if let vm = viewModel, let cat = vm.selectedCategory,
               let item = vm.categoryTotals.first(where: { $0.category.id == cat.id }) {
                CategoryDrillDownSheet(
                    category: cat,
                    categoryMinorUnits: item.minorUnits,
                    periodExpenses: vm.periodExpenses,
                    homeCurrencyCode: vm.homeCurrencyCode,
                    period: vm.period
                )
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ vm: InsightsViewModel) -> some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                periodPicker(vm)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider()
            }
            .background(.bar)

            ScrollView {
                VStack(spacing: 0) {
                    if vm.isLoading && vm.categoryTotals.isEmpty {
                        ProgressView()
                            .padding(.vertical, 40)
                    } else {
                        Group {
                            // Trend + heatmap lead; the category donut — the universal
                            // expense-tracker visual — is demoted to the bottom.
                            trendSection(vm)
                            heatmapSection(vm)
                            if vm.period == .month {
                                budgetSection(vm)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                            topMerchantSection(vm)
                            donutSection(vm)
                        }
                        .id(vm.period)
                        .transition(.opacity)
                        .opacity(vm.isLoading ? 0.55 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: vm.isLoading)
                        .animation(.easeInOut(duration: 0.25), value: vm.period)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .task(id: vm.period) {
            selectedAngleValue = nil
            vm.selectedCategory = nil
            await vm.refresh()
        }
    }

    // MARK: - Period picker

    private func periodPicker(_ vm: InsightsViewModel) -> some View {
        @Bindable var vm = vm
        return Picker(String(localized: "Period"), selection: $vm.period) {
            ForEach(InsightsViewModel.Period.allCases) { p in
                Text(p.shortName).tag(p)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Donut chart section

    private func donutSection(_ vm: InsightsViewModel) -> some View {
        GroupBox {
            if vm.categoryTotals.isEmpty {
                emptyLabel
            } else {
                VStack(spacing: 14) {
                    donutChart(vm)
                    if let sel = vm.selectedCategory,
                       let item = vm.categoryTotals.first(where: { $0.category.id == sel.id }) {
                        callout(item: item, vm: vm)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }
                    categoryLegend(vm)
                }
                .animation(.easeInOut(duration: 0.2), value: vm.selectedCategory?.id)
            }
        } label: {
            Label(String(localized: "Spending by Category"), systemImage: "chart.pie.fill")
                .font(.headline)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func donutChart(_ vm: InsightsViewModel) -> some View {
        ZStack {
            Chart(vm.categoryTotals, id: \.category.id) { item in
                SectorMark(
                    angle: .value(String(localized: "Amount"), item.minorUnits),
                    innerRadius: .ratio(0.64),
                    angularInset: vm.categoryTotals.count == 1 ? 0 : 1.5
                )
                .foregroundStyle(Color(hex: item.category.colorHex))
                .opacity(sectorOpacity(item.category, selected: vm.selectedCategory))
            }
            .chartLegend(.hidden)
            .chartAngleSelection(value: $selectedAngleValue)
            .onChange(of: selectedAngleValue) { _, v in
                vm.selectedCategory = v.flatMap { categoryForAngle($0, totals: vm.categoryTotals) }
            }
            // Swift Charts doesn't auto-describe sectors; provide a manual label
            .accessibilityLabel(
                String(localized: "\(vm.categoryTotals.count) categories, total \(Money(minorUnits: vm.periodTotalMinor, currencyCode: vm.homeCurrencyCode).formatted())")
            )

            VStack(spacing: 2) {
                if let sel = vm.selectedCategory,
                   let item = vm.categoryTotals.first(where: { $0.category.id == sel.id }) {
                    let pct = vm.periodTotalMinor > 0
                        ? Int(round(Double(item.minorUnits) / Double(vm.periodTotalMinor) * 100))
                        : 0
                    Text(item.category.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: 120)
                    Text(Money(minorUnits: item.minorUnits, currencyCode: vm.homeCurrencyCode).formatted())
                        .font(.system(.callout, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .frame(maxWidth: 132)
                    Text("\(pct)%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(localized: "Total"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Money(minorUnits: vm.periodTotalMinor, currencyCode: vm.homeCurrencyCode).formatted())
                        .font(.system(.callout, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .frame(maxWidth: 132)
                        .contentTransition(.numericText(value: Double(vm.periodTotalMinor)))
                        .animation(.easeInOut(duration: 0.3), value: vm.periodTotalMinor)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: vm.selectedCategory?.id)
        }
        .frame(height: 210)
    }

    private func callout(item: (category: Category, minorUnits: Int), vm: InsightsViewModel) -> some View {
        let pct = vm.periodTotalMinor > 0
            ? Int(round(Double(item.minorUnits) / Double(vm.periodTotalMinor) * 100))
            : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: item.category.iconName)
                    .foregroundStyle(Color(hex: item.category.colorHex))
                    .frame(width: 24)
                Text(item.category.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(pct)%  ·  \(Money(minorUnits: item.minorUnits, currencyCode: vm.homeCurrencyCode).formatted())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Button(String(localized: "View Details")) {
                showDrillDown = true
            }
            .font(.caption)
            .foregroundStyle(Color.accentColor)
        }
        .padding(10)
        .background(Color(.secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func categoryLegend(_ vm: InsightsViewModel) -> some View {
        VStack(spacing: 8) {
            ForEach(vm.categoryTotals, id: \.category.id) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: item.category.colorHex))
                        .frame(width: 10, height: 10)
                    Text(item.category.name)
                        .font(.subheadline)
                    Spacer()
                    Text(Money(minorUnits: item.minorUnits, currencyCode: vm.homeCurrencyCode).formatted())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if vm.selectedCategory?.id == item.category.id {
                        vm.selectedCategory = nil
                        selectedAngleValue = nil
                    } else {
                        vm.selectedCategory = item.category
                        selectedAngleValue = nil
                    }
                }
                .opacity(vm.selectedCategory.map { $0.id == item.category.id ? 1.0 : 0.4 } ?? 1.0)
            }
        }
    }

    // MARK: - Trend chart section

    private func trendSection(_ vm: InsightsViewModel) -> some View {
        GroupBox {
            if vm.dailyTotals.isEmpty {
                emptyLabel
            } else {
                trendChart(vm)
            }
        } label: {
            Label(String(localized: "Spending Over Time"), systemImage: "chart.bar.fill")
                .font(.headline)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func trendChart(_ vm: InsightsViewModel) -> some View {
        let byMonth = vm.period == .year || vm.period == .allTime
        let totals  = vm.dailyTotals
        let avg     = totals.isEmpty ? 0 : totals.reduce(0) { $0 + $1.minorUnits } / totals.count
        let unit: Calendar.Component = byMonth ? .month : .day
        let xFmt: Date.FormatStyle = byMonth
            ? .dateTime.month(.abbreviated)
            : .dateTime.month(.abbreviated).day()

        return Chart {
            ForEach(totals, id: \.date) { item in
                BarMark(
                    x: .value(byMonth ? String(localized: "Month") : String(localized: "Day"), item.date, unit: unit),
                    y: .value(String(localized: "Amount"), item.minorUnits)
                )
                .foregroundStyle(Color.accentColor)
                .cornerRadius(3)
            }
            if avg > 0 {
                RuleMark(y: .value(String(localized: "Average"), avg))
                    .foregroundStyle(.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text(String(localized: "Avg"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .background(.background.opacity(0.6), in: Capsule())
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: totals.count == 1 ? 1 : 6)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: xFmt)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    let minor: Int? = value.as(Int.self) ?? value.as(Double.self).map { Int($0) }
                    if let minor {
                        Text(compactAmount(minor, currency: vm.homeCurrencyCode))
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .frame(height: 180)
    }

    // MARK: - Budget section

    private func budgetSection(_ vm: InsightsViewModel) -> some View {
        let entries = budgetEntries(from: vm)
        return GroupBox {
            if entries.isEmpty {
                Text(String(localized: "Set budgets in Settings to track progress."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 14) {
                    ForEach(entries, id: \.category.id) { entry in
                        budgetRow(entry)
                    }
                }
            }
        } label: {
            HStack {
                Label(String(localized: "Budget Progress"), systemImage: "chart.bar.xaxis")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    BudgetsSettingsView()
                } label: {
                    Text(String(localized: "Manage"))
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func budgetRow(_ entry: BudgetEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: entry.category.iconName)
                    .foregroundStyle(Color(hex: entry.category.colorHex))
                    .frame(width: 20)
                Text(entry.category.name)
                    .font(.subheadline)
                Spacer()
                Text("\(Money(minorUnits: entry.spentMinor, currencyCode: entry.currencyCode).formatted()) / \(Money(minorUnits: entry.budgetMinor, currencyCode: entry.currencyCode).formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            ProgressView(value: entry.clampedProgress)
                .tint(entry.progressColor)
                .accessibilityLabel("\(entry.category.name) budget: \(Int(entry.clampedProgress * 100))% used")
        }
    }

    // MARK: - Heatmap section

    private func heatmapSection(_ vm: InsightsViewModel) -> some View {
        GroupBox {
            SpendingHeatmapSection(
                dailyTotals: vm.heatmapDailyTotals,
                currencyCode: vm.homeCurrencyCode
            )
        } label: {
            Label(String(localized: "Daily Activity"), systemImage: "calendar.badge.clock")
                .font(.headline)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Top merchant section

    private func topMerchantSection(_ vm: InsightsViewModel) -> some View {
        GroupBox {
            if let top = vm.topMerchant {
                HStack(spacing: 4) {
                    Text(top.merchant)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Money(minorUnits: top.minorUnits, currencyCode: vm.homeCurrencyCode).formatted())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            } else {
                Text(String(localized: "No merchant data in this period"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
        } label: {
            Label(String(localized: "Top Merchant"), systemImage: "trophy.fill")
                .font(.headline)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var emptyLabel: some View {
        VStack(spacing: 12) {
            Text(String(localized: "No expenses in this period"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            Button(String(localized: "Add an Expense")) {
                NotificationCenter.default.post(
                    name: Notification.Name("LedgerLiteDeepLink"),
                    object: URL(string: "ledgerlite://today")
                )
            }
            .font(.subheadline)
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func sectorOpacity(_ category: Category, selected: Category?) -> Double {
        guard let sel = selected else { return 1.0 }
        return sel.id == category.id ? 1.0 : 0.3
    }

    private func categoryForAngle(_ value: Int, totals: [(category: Category, minorUnits: Int)]) -> Category? {
        var cumulative = 0
        for item in totals {
            cumulative += item.minorUnits
            if value <= cumulative { return item.category }
        }
        return totals.last?.category
    }

    private func budgetEntries(from vm: InsightsViewModel) -> [BudgetEntry] {
        vm.allCategories
            .filter { $0.monthlyBudgetMinor != nil }
            .compactMap { cat in
                guard let budget = cat.monthlyBudgetMinor else { return nil }
                let spent = vm.categoryTotals.first(where: { $0.category.id == cat.id })?.minorUnits ?? 0
                return BudgetEntry(
                    category: cat,
                    spentMinor: spent,
                    budgetMinor: budget,
                    currencyCode: vm.homeCurrencyCode
                )
            }
    }

    private static var compactFormatters: [String: NumberFormatter] = [:]
    private func compactAmount(_ minorUnits: Int, currency: String) -> String {
        let formatter: NumberFormatter
        if let cached = Self.compactFormatters[currency] {
            formatter = cached
        } else {
            let fmt = NumberFormatter()
            fmt.numberStyle = .currency
            fmt.currencyCode = currency
            fmt.locale = .current
            fmt.maximumFractionDigits = 0
            fmt.minimumFractionDigits = 0
            Self.compactFormatters[currency] = fmt
            formatter = fmt
        }
        let places = Money.decimals(for: currency)
        var divisor = Decimal(1)
        for _ in 0..<places { divisor *= 10 }
        let value = Decimal(minorUnits) / divisor
        return formatter.string(from: value as NSDecimalNumber) ?? "\(minorUnits)"
    }

    // MARK: - Share image

    @MainActor
    private func shareInsightsSummary(_ vm: InsightsViewModel) {
        let card = SummaryShareCardView(vm: vm)
        let renderer = ImageRenderer(content: card.frame(width: 360))
        renderer.scale = displayScale
        if let image = renderer.uiImage {
            shareItems = [image]
        } else {
            shareItems = [shareText(vm)]
        }
        showShareSheet = true
    }

    // MARK: - Share text (fallback)

    private func shareText(_ vm: InsightsViewModel) -> String {
        var lines: [String] = [
            "LedgerLite — \(vm.period.displayName)",
            "Total: \(Money(minorUnits: vm.periodTotalMinor, currencyCode: vm.homeCurrencyCode).formatted())",
            ""
        ]
        for item in vm.categoryTotals {
            let pct = vm.periodTotalMinor > 0
                ? Int(round(Double(item.minorUnits) / Double(vm.periodTotalMinor) * 100))
                : 0
            lines.append("• \(item.category.name): \(Money(minorUnits: item.minorUnits, currencyCode: vm.homeCurrencyCode).formatted()) (\(pct)%)")
        }
        if let top = vm.topMerchant {
            lines.append("")
            lines.append("Top merchant: \(top.merchant) (\(Money(minorUnits: top.minorUnits, currencyCode: vm.homeCurrencyCode).formatted()))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Budget entry

    private struct BudgetEntry {
        let category: Category
        let spentMinor: Int
        let budgetMinor: Int
        let currencyCode: String

        var clampedProgress: Double {
            budgetMinor > 0 ? min(1.0, Double(spentMinor) / Double(budgetMinor)) : 0
        }

        var progressColor: Color {
            guard budgetMinor > 0 else { return .green }
            let ratio = Double(spentMinor) / Double(budgetMinor)
            if ratio >= 1.0  { return .red }
            if ratio >= 0.80 { return .orange }
            return .green
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        InsightsView()
            .modelContainer(PreviewContainer.shared)
    }
}
#endif
