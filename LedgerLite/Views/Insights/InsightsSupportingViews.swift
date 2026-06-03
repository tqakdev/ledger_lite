import SwiftUI
import UIKit

// Supporting views extracted from InsightsView to keep that file focused on the
// dashboard itself. Each is self-contained and depends only on module types.

// MARK: - Summary Share Card

struct SummaryShareCardView: View {
    let vm: InsightsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Ledger Lite")
                    .font(.headline)
                Spacer()
                Text(vm.period.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Total"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Money(minorUnits: vm.periodTotalMinor, currencyCode: vm.homeCurrencyCode).formatted())
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }

            if !vm.categoryTotals.isEmpty {
                Divider()
                VStack(spacing: 8) {
                    ForEach(vm.categoryTotals.prefix(5), id: \.category.id) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: item.category.colorHex))
                                .frame(width: 8, height: 8)
                            Text(item.category.name)
                                .font(.subheadline)
                            Spacer()
                            let pct = vm.periodTotalMinor > 0
                                ? Int(round(Double(item.minorUnits) / Double(vm.periodTotalMinor) * 100))
                                : 0
                            Text("\(Money(minorUnits: item.minorUnits, currencyCode: vm.homeCurrencyCode).formatted())  \(pct)%")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }

            if let top = vm.topMerchant {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                    Text(top.merchant).font(.subheadline).fontWeight(.medium).lineLimit(1)
                    Spacer()
                    Text(Money(minorUnits: top.minorUnits, currencyCode: vm.homeCurrencyCode).formatted())
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Activity Sheet (Insights)

struct InsightsActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Spending Heatmap

/// 13-week rolling heatmap (GitHub contribution-graph style).
/// Each cell represents one calendar day; colour intensity is proportional to
/// that day's spending relative to the user's personal peak day in the window.
struct SpendingHeatmapSection: View {
    let dailyTotals: [Date: Int]   // startOfDay → home-currency minor units
    let currencyCode: String

    private let weeks = 13
    private let cellSize: CGFloat = 13
    private let gap: CGFloat = 3
    private let cal = Calendar.current

    private var todayStart: Date { cal.startOfDay(for: Date()) }

    // First day of the calendar week containing today (respects locale firstWeekday).
    private var startOfCurrentWeek: Date {
        let weekday = cal.component(.weekday, from: todayStart)
        let offset  = (weekday - cal.firstWeekday + 7) % 7
        return cal.date(byAdding: .day, value: -offset, to: todayStart) ?? todayStart
    }

    // Top-left corner of the grid: (weeks - 1) full weeks before the current week.
    private var gridStart: Date {
        cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: startOfCurrentWeek) ?? todayStart
    }

    // [column 0…weeks-1][row 0…6]  — column 0 = oldest week, row 0 = first weekday
    private var gridDates: [[Date]] {
        (0..<weeks).map { col in
            (0..<7).map { row in
                cal.date(byAdding: .day, value: col * 7 + row, to: gridStart) ?? gridStart
            }
        }
    }

    private var maxMinor: Int { dailyTotals.values.max() ?? 0 }

    private func cellColor(for date: Date) -> Color {
        // Future cells are invisible — current week may be partial.
        if date > todayStart { return Color.clear }
        guard let minor = dailyTotals[date], minor > 0, maxMinor > 0 else {
            return Color(.systemFill)
        }
        let ratio = Double(minor) / Double(maxMinor)
        if ratio < 0.25 { return Color.accentColor.opacity(0.30) }
        if ratio < 0.50 { return Color.accentColor.opacity(0.55) }
        if ratio < 0.75 { return Color.accentColor.opacity(0.75) }
        return Color.accentColor
    }

    // Returns the abbreviated month name to show above a column when the month changes.
    private func monthLabel(for col: Int) -> String? {
        let date = gridDates[col][0]
        guard col == 0 || cal.component(.month, from: date)
                       != cal.component(.month, from: gridDates[col - 1][0])
        else { return nil }
        return date.formatted(.dateTime.month(.abbreviated))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: gap) {
                ForEach(0..<weeks, id: \.self) { col in
                    VStack(spacing: gap) {
                        // Month label row — same height for every column so cells align.
                        Group {
                            if let label = monthLabel(for: col) {
                                Text(label)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: cellSize, height: 11)

                        // Day cells
                        ForEach(0..<7, id: \.self) { row in
                            let date = gridDates[col][row]
                            RoundedRectangle(cornerRadius: 2)
                                .fill(cellColor(for: date))
                                .overlay {
                                    // Today gets an accent border.
                                    if date.isSameDay(as: todayStart) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(Color.accentColor, lineWidth: 1)
                                    }
                                }
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }

            // Intensity legend
            HStack(spacing: 4) {
                Text(String(localized: "Less"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach([Double(0), 0.30, 0.55, 0.75, 1.0], id: \.self) { opacity in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(opacity == 0 ? Color(.systemFill) : Color.accentColor.opacity(opacity))
                        .frame(width: cellSize, height: cellSize)
                }
                Text(String(localized: "More"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("13-week spending activity heatmap in \(currencyCode)"))
    }
}

// MARK: - Category Drill-Down Sheet

struct CategoryDrillDownSheet: View {
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
