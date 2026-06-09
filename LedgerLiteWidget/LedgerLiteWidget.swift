import WidgetKit
import SwiftUI

// MARK: - Today Widget ─────────────────────────────────────────────────────────

struct LedgerLiteEntry: TimelineEntry {
    let date: Date
    let summary: WidgetDataService.TodaySummary?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> LedgerLiteEntry {
        LedgerLiteEntry(date: .now, summary: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (LedgerLiteEntry) -> Void) {
        completion(LedgerLiteEntry(date: .now, summary: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LedgerLiteEntry>) -> Void) {
        Task { @MainActor in
            let summary = WidgetDataService()?.todaySummary()
            let entry   = LedgerLiteEntry(date: .now, summary: summary)
            let next    = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

// MARK: Today entry view

struct LedgerLiteTodayWidgetEntryView: View {
    let entry: LedgerLiteEntry
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        switch widgetFamily {
        case .systemMedium:         mediumView
        case .accessoryRectangular: accessoryRectangularView
        case .accessoryCircular:    accessoryCircularView
        default:                    smallView
        }
    }

    // MARK: Lock screen — circular

    private var accessoryCircularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let summary = entry.summary {
                VStack(spacing: 0) {
                    Image(systemName: "dollarsign")
                        .font(.caption2.weight(.semibold))
                    Text(Money(minorUnits: summary.totalMinor, currencyCode: summary.currencyCode)
                            .formatted())
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "dollarsign.circle")
                    .font(.title3)
            }
        }
        .widgetURL(URL(string: "ledgerlite://today")!)
    }

    // MARK: Lock screen — rectangular

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Today's Total"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let summary = entry.summary {
                Text(Money(minorUnits: summary.totalMinor, currencyCode: summary.currencyCode).formatted())
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                let count = summary.expenses.count
                // Pluralised via Localizable.stringsdict ("%lld expenses").
                Text(String(localized: "\(count) expenses"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("$0.00")
                    .font(.headline.bold())
                    .redacted(reason: .placeholder)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "ledgerlite://today")!)
    }

    // MARK: Small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "LedgerLite"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if let summary = entry.summary {
                Text(String(localized: "Today's Total"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(Money(minorUnits: summary.totalMinor, currencyCode: summary.currencyCode).formatted())
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                Spacer()
                let count = summary.expenses.count
                // Pluralised via Localizable.stringsdict ("%lld expenses").
                Text(String(localized: "\(count) expenses"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("$0.00")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .redacted(reason: .placeholder)
                Text("0 expenses")
                    .font(.caption)
                    .redacted(reason: .placeholder)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "ledgerlite://today")!)
    }

    // MARK: Medium

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "Today's Total"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let summary = entry.summary {
                        Text(Money(minorUnits: summary.totalMinor, currencyCode: summary.currencyCode).formatted())
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    } else {
                        Text(String(localized: "No data"))
                            .font(.title2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let summary = entry.summary {
                    let count = summary.expenses.count
                    Text(count == 1
                         ? String(localized: "1 expense")
                         : String(localized: "\(count) expenses"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()

            // Expense rows
            if let summary = entry.summary, !summary.expenses.isEmpty {
                VStack(spacing: 0) {
                    ForEach(summary.expenses) { snap in
                        Link(destination: URL(string: "ledgerlite://expense/\(snap.id)")!) {
                            expenseRow(snap)
                        }
                        if snap.id != summary.expenses.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            } else {
                Text(String(localized: "No expenses today"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "ledgerlite://today")!)
    }

    private func expenseRow(_ snap: WidgetDataService.ExpenseSnapshot) -> some View {
        let hex  = snap.categoryColorHex ?? "#BDC3C7"
        let icon = snap.categoryIconName ?? "square.grid.2x2.fill"
        let label = snap.merchant ?? snap.note ?? snap.categoryName ?? String(localized: "Expense")
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(hex: hex).opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(Color(hex: hex))
            }
            Text(label)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(Money(minorUnits: snap.amountMinor, currencyCode: snap.currencyCode).formatted())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(snap.date.formatted(.dateTime.hour().minute()))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: Today widget configuration

struct LedgerLiteTodayWidget: Widget {
    let kind = "LedgerLiteTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            LedgerLiteTodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Today's Spending"))
        .description(String(localized: "See today's expenses at a glance."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Subscriptions Widget ─────────────────────────────────────────────────

struct SubscriptionsEntry: TimelineEntry {
    let date: Date
    let upcoming: [WidgetDataService.SubscriptionSnapshot]
}

struct SubscriptionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> SubscriptionsEntry {
        SubscriptionsEntry(date: .now, upcoming: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (SubscriptionsEntry) -> Void) {
        completion(SubscriptionsEntry(date: .now, upcoming: []))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SubscriptionsEntry>) -> Void) {
        Task { @MainActor in
            let upcoming = WidgetDataService()?.upcomingSubscriptions(limit: 3) ?? []
            let entry    = SubscriptionsEntry(date: .now, upcoming: upcoming)
            let next     = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

// MARK: Subscriptions entry view

struct LedgerLiteSubscriptionsWidgetEntryView: View {
    let entry: SubscriptionsEntry
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        switch widgetFamily {
        case .systemMedium: mediumView
        default:            smallView
        }
    }

    // MARK: Small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Next Billing"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if let sub = entry.upcoming.first {
                Text(sub.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(Money(minorUnits: sub.amountMinor, currencyCode: sub.currencyCode).formatted())
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Spacer()
                daysBadge(for: sub.nextBillingDate)
                    .font(.caption)
            } else {
                Text(String(localized: "No subscriptions"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "ledgerlite://subscriptions")!)
    }

    // MARK: Medium

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Upcoming Bills"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            if entry.upcoming.isEmpty {
                Text(String(localized: "No active subscriptions"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(entry.upcoming) { sub in
                        Link(destination: URL(string: "ledgerlite://subscriptions")!) {
                            subscriptionRow(sub)
                        }
                        if sub.id != entry.upcoming.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "ledgerlite://subscriptions")!)
    }

    private func subscriptionRow(_ sub: WidgetDataService.SubscriptionSnapshot) -> some View {
        let hex = sub.categoryColorHex ?? "#BDC3C7"
        return HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 10, height: 10)
            Text(sub.name)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(Money(minorUnits: sub.amountMinor, currencyCode: sub.currencyCode).formatted())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            daysBadge(for: sub.nextBillingDate)
                .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func daysBadge(for date: Date) -> some View {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0

        switch days {
        case 0:
            Text(String(localized: "Today"))
                .foregroundStyle(.red)
        case 1:
            Text(String(localized: "Tomorrow"))
                .foregroundStyle(.orange)
        case 2...7:
            Text(String(localized: "In \(days) days"))
                .foregroundStyle(.orange)
        default:
            Text(String(localized: "In \(days) days"))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: Subscriptions widget configuration

struct LedgerLiteSubscriptionsWidget: Widget {
    let kind = "LedgerLiteSubscriptionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SubscriptionsProvider()) { entry in
            LedgerLiteSubscriptionsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Upcoming Bills"))
        .description(String(localized: "See your next subscription billing dates."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Payday Runway Widget ─────────────────────────────────────────────────

struct RunwayWidgetEntry: TimelineEntry {
    let date: Date
    let safeToSpendMinor: Int?
    let currencyCode: String
    let isConfigured: Bool
}

struct RunwayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RunwayWidgetEntry {
        RunwayWidgetEntry(date: .now, safeToSpendMinor: 4200, currencyCode: "USD", isConfigured: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (RunwayWidgetEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RunwayWidgetEntry>) -> Void) {
        let entry = makeEntry()
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> RunwayWidgetEntry {
        RunwayWidgetEntry(
            date: .now,
            safeToSpendMinor: UserPreferences.cachedSafeToSpendMinor,
            currencyCode: UserPreferences.homeCurrencyCode,
            isConfigured: UserPreferences.hasRunwaySetup
        )
    }
}

struct LedgerLiteRunwayWidgetEntryView: View {
    let entry: RunwayWidgetEntry
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        switch widgetFamily {
        case .accessoryRectangular: accessoryRectangularView
        default:                    smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Payday Runway"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if entry.isConfigured, let minor = entry.safeToSpendMinor {
                Text(String(localized: "Safe to spend"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(Money(minorUnits: minor, currencyCode: entry.currencyCode).formatted())
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.mint)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer()
                Text(String(localized: "/ day to payday"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text(String(localized: "Set up runway"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "ledgerlite://runway")!)
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Safe to spend / day"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if entry.isConfigured, let minor = entry.safeToSpendMinor {
                Text(Money(minorUnits: minor, currencyCode: entry.currencyCode).formatted())
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                Text(String(localized: "to payday"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "Runway not set up"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "ledgerlite://runway")!)
    }
}

struct LedgerLiteRunwayWidget: Widget {
    let kind = "LedgerLiteRunwayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RunwayWidgetProvider()) { entry in
            LedgerLiteRunwayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Payday Runway"))
        .description(String(localized: "Your daily safe-to-spend after upcoming bills — calculated on-device, no bank login."))
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}
