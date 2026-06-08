import SwiftUI

struct SubscriptionRowView: View {
    let subscription: Subscription
    let notificationsAuthorized: Bool
    var homeAmountMinor: Int? = nil
    var homeCurrencyCode: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    private var daysUntil: Int {
        let components = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: subscription.nextBillingDate)
        )
        return max(0, components.day ?? 0)
    }

    private var daysLabel: String {
        switch daysUntil {
        case 0:  return String(localized: "Today")
        case 1:  return String(localized: "Tomorrow")
        default: return String(localized: "In \(daysUntil) days")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            categoryIcon
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    Text(subscription.name)
                        .font(.body)
                        .lineLimit(1)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(subscription.money.formatted())
                            .font(.body)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(subscription.money.minorUnits)))
                            .animation(.spring(duration: 0.3, bounce: 0.2), value: subscription.money.minorUnits)
                        if let homeMinor = homeAmountMinor,
                           !homeCurrencyCode.isEmpty,
                           subscription.currencyCode != homeCurrencyCode {
                            Text("≈ \(Money(minorUnits: homeMinor, currencyCode: homeCurrencyCode).formatted())")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                HStack {
                    Text(subscription.billingCycle.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    statusBadge
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(subscription.name), \(subscription.money.formatted()), \(daysLabel)")
    }

    private var categoryIcon: some View {
        let hex  = subscription.category?.colorHex ?? "#BDC3C7"
        let icon = subscription.category?.iconName  ?? "repeat.circle.fill"
        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: hex).opacity(0.15))
                .frame(width: 44, height: 44)
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(Color(hex: hex))
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch subscription.status {
        case .active:
            HStack(spacing: 4) {
                if !notificationsAuthorized {
                    Image(systemName: "bell.slash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(daysLabel)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(daysUntil <= 2 ? Theme.caution : .secondary)
                    .scaleEffect(pulsing && daysUntil <= 2 ? 1.08 : 1.0)
                    .onAppear {
                        guard daysUntil <= 2, !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            pulsing = true
                        }
                    }
            }
            .padding(.horizontal, daysUntil <= 2 ? 6 : 0)
            .padding(.vertical, daysUntil <= 2 ? 2 : 0)
            .background(daysUntil <= 2 ? Theme.caution.opacity(0.1) : Color.clear)
            .clipShape(Capsule())
        case .paused:
            Text(String(localized: "Paused"))
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.caution.opacity(0.2))
                .foregroundStyle(Theme.caution)
                .clipShape(Capsule())
        case .cancelled:
            Text(String(localized: "Cancelled"))
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.danger.opacity(0.1))
                .foregroundStyle(Theme.danger)
                .clipShape(Capsule())
        }
    }
}

extension BillingCycle {
    var displayName: String {
        switch self {
        case .weekly:            return String(localized: "Weekly")
        case .monthly:           return String(localized: "Monthly")
        case .yearly:            return String(localized: "Yearly")
        case .customDays(let n): return String(localized: "Every \(n) days")
        }
    }
}
