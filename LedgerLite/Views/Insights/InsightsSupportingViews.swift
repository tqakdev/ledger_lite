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
                Text("LedgerLite")
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
