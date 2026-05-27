import SwiftUI

struct ExpenseRowView: View {
    let expense: Expense
    let homeCurrencyCode: String

    private var timeText: String {
        expense.date.formatted(date: .omitted, time: .shortened)
    }

    private var dateLabel: String? {
        guard !Calendar.current.isDateInToday(expense.date) else { return nil }
        if Calendar.current.isDateInYesterday(expense.date) {
            return String(localized: "Yesterday")
        }
        return expense.date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var subtitle: String {
        if let merchant = expense.merchant, !merchant.isEmpty { return merchant }
        if let note = expense.note, !note.isEmpty { return note }
        return expense.category?.name ?? String(localized: "Expense")
    }

    var body: some View {
        HStack(spacing: 12) {
            categoryIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let dateLabel {
                        Text(dateLabel)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text(timeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(expense.money.formatted())
                    .font(.body)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .accessibilityLabel("\(subtitle), \(expense.money.formatted()), \(timeText)")
                if expense.currencyCode != homeCurrencyCode {
                    Text(homeEquivalent)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if expense.needsRateRefresh {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .accessibilityLabel(String(localized: "Rate pending refresh"))
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var categoryIcon: some View {
        let hex  = expense.category?.colorHex ?? "#BDC3C7"
        let icon = expense.category?.iconName  ?? "square.grid.2x2.fill"
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: hex).opacity(0.15))
                .frame(width: 44, height: 44)
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(Color(hex: hex))
        }
        .accessibilityHidden(true)
    }

    private var homeEquivalent: String {
        expense.money.converted(to: homeCurrencyCode, rate: expense.exchangeRateToHome).formatted()
    }
}
