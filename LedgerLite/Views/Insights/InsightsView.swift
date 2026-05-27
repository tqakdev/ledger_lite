import SwiftUI
import Charts
import SwiftData

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: InsightsViewModel?
    @State private var selectedAngleValue: Int?
    @State private var showDrillDown = false
    // C3
    @State private var showError = false
    @State private var errorText = ""

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    content(vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(String(localized: "Insights"))
            .navigationBarTitleDisplayMode(.large)  // A9
            .toolbar {
                if let vm = viewModel, !vm.categoryTotals.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: shareText(vm)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = InsightsViewModel(context: modelContext)
            }
            Task { await viewModel?.refresh() }
        }
        // C3
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

    private func content(_ vm: InsightsViewModel) -> some View {
        VStack(spacing: 0) {
            periodPicker(vm)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    if vm.isLoading && vm.categoryTotals.isEmpty {
                        ProgressView()
                            .padding(.vertical, 40)
                    } else {
                        Group {
                            donutSection(vm)
                            trendSection(vm)
                            if vm.period == .month {
                                budgetSection(vm)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                            topMerchantSection(vm)
                        }
                        .opacity(vm.isLoading ? 0.55 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: vm.isLoading)
                        .animation(.easeInOut(duration: 0.2), value: vm.period)
                    }
                }
            }
        }
        .onChange(of: vm.period) { _, _ in
            selectedAngleValue = nil
            vm.selectedCategory = nil
            Task { await vm.refresh() }
        }
    }

    // MARK: - Period picker

    private func periodPicker(_ vm: InsightsViewModel) -> some View {
        Picker(String(localized: "Period"), selection: Binding(
            get: { vm.period },
            set: { vm.period = $0 }
        )) {
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
        .padding(.top, 4)
    }

    private func donutChart(_ vm: InsightsViewModel) -> some View {
        ZStack {
            Chart(vm.categoryTotals, id: \.category.id) { item in
                SectorMark(
                    angle: .value(String(localized: "Amount"), item.minorUnits),
                    innerRadius: .ratio(0.56),
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
            // C2: manual accessibility label for donut (Swift Charts doesn't auto-describe it)
            .accessibilityLabel(
                String(localized: "\(vm.categoryTotals.count) categories, total \(Money(minorUnits: vm.periodTotalMinor, currencyCode: vm.homeCurrencyCode).formatted())")
            )

            VStack(spacing: 2) {
                Text(String(localized: "Total"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Money(minorUnits: vm.periodTotalMinor, currencyCode: vm.homeCurrencyCode).formatted())
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: 120)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: vm.periodTotalMinor)
            }
        }
        .frame(height: 220)
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
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text(String(localized: "Avg"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
            Label(String(localized: "Budget Progress"), systemImage: "chart.bar.xaxis")
                .font(.headline)
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

    // MARK: - Top merchant section

    private func topMerchantSection(_ vm: InsightsViewModel) -> some View {
        GroupBox {
            if let top = vm.topMerchant {
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(.yellow)
                        .frame(width: 24)
                    Text(top.merchant)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer(minLength: 4)
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
            Label(String(localized: "Top Merchant"), systemImage: "trophy")
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

    // MARK: - Share text

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

// MARK: - Category Drill-Down Sheet

private struct CategoryDrillDownSheet: View {
    @Environment(\.dismiss) private var dismiss
    let category: Category
    let categoryMinorUnits: Int
    let periodExpenses: [Expense]
    let homeCurrencyCode: String
    let period: InsightsViewModel.Period

    private var expenses: [Expense] {
        periodExpenses
            .filter { $0.category?.id == category.id }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text(String(localized: "Total"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(Money(minorUnits: categoryMinorUnits, currencyCode: homeCurrencyCode).formatted())
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                } header: {
                    Text(period.displayName)
                }

                Section {
                    if expenses.isEmpty {
                        Text(String(localized: "No expenses"))
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(expenses, id: \.id) { expense in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(expense.merchant ?? String(localized: "Unnamed"))
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text(expense.date.formatted(.dateTime.month(.abbreviated).day().year()))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(expense.money.formatted())
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(category.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#if DEBUG
#Preview {
    InsightsView()
        .modelContainer(PreviewContainer.shared)
}
#endif
