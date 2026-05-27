import SwiftUI
import SwiftData

struct BudgetsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("homeCurrencyCode") private var homeCurrencyCode = Constants.App.homeCurrencyDefault
    @State private var categories: [Category] = []

    var body: some View {
        List {
            Section {
                ForEach(categories, id: \.id) { category in
                    BudgetRow(category: category, homeCurrencyCode: homeCurrencyCode)
                }
            } footer: {
                Text(String(localized: "Amounts in \(homeCurrencyCode). Leave blank to remove a budget."))
                    .font(.caption)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "Monthly Budgets"))
        .navigationBarTitleDisplayMode(.large)
        .onAppear { loadCategories() }
    }

    private func loadCategories() {
        do {
            categories = try CategoryRepository(context: modelContext).fetchAll()
        } catch {
            AppLogger.data.error("BudgetsSettingsView load failed: \(error)")
        }
    }
}

// MARK: - Budget row

private struct BudgetRow: View {
    @Environment(\.modelContext) private var modelContext
    let category: Category
    let homeCurrencyCode: String

    @State private var text: String = ""
    private var parser: AmountInputParser { AmountInputParser(currencyCode: homeCurrencyCode, locale: .current) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: category.colorHex).opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: category.iconName)
                    .font(.subheadline)
                    .foregroundStyle(Color(hex: category.colorHex))
            }
            Text(category.name)
                .font(.body)
            Spacer()
            TextField(String(localized: "No limit"), text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(width: 96)
                .onSubmit { commitBudget() }
                .onChange(of: text) { _, newValue in
                    let (display, _) = parser.parse(newValue)
                    if newValue != display { text = display }
                }
            Text(homeCurrencyCode)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            if let budget = category.monthlyBudgetMinor {
                text = parser.format(minorUnits: budget)
            }
        }
        .onDisappear { commitBudget() }
    }

    private func commitBudget() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            category.monthlyBudgetMinor = nil
        } else {
            let (_, minorUnits) = parser.parse(trimmed)
            category.monthlyBudgetMinor = minorUnits > 0 ? minorUnits : nil
        }
        do {
            try modelContext.save()
        } catch {
            AppLogger.data.error("Budget save failed: \(error)")
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BudgetsSettingsView()
    }
    .modelContainer(PreviewContainer.shared)
}
#endif
