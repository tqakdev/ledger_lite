import SwiftUI

struct SubscriptionRowView: View {
    let subscription: Subscription
    let notificationsAuthorized: Bool

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
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Tomorrow")
        default: return String(localized: "In \(daysUntil) days")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            categoryIcon
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(subscription.name)
                        .font(.body)
                    Spacer()
                    Text(subscription.money.formatted())
                        .font(.body)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                HStack {
                    Text(subscription.billingCycle.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    statusBadge
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var categoryIcon: some View {
        Group {
            if let cat = subscription.category {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: cat.colorHex).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: cat.iconName)
                        .font(.body)
                        .foregroundStyle(Color(hex: cat.colorHex))
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "repeat.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
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
                    .foregroundStyle(daysUntil <= 2 ? .orange : .secondary)
                    .scaleEffect(pulsing && daysUntil <= 2 ? 1.08 : 1.0)
                    .onAppear {
                        guard daysUntil <= 2 else { return }
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            pulsing = true
                        }
                    }
            }
        case .paused:
            Text(String(localized: "Paused"))
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.yellow.opacity(0.2))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        case .cancelled:
            Text(String(localized: "Cancelled"))
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.red.opacity(0.1))
                .foregroundStyle(.red)
                .clipShape(Capsule())
        }
    }
}

extension BillingCycle {
    var displayName: String {
        switch self {
        case .weekly: return String(localized: "Weekly")
        case .monthly: return String(localized: "Monthly")
        case .yearly: return String(localized: "Yearly")
        case .customDays(let n): return String(localized: "Every \(n) days")
        }
    }
}
