import SwiftUI
import SwiftData

private enum CalendarMode: Equatable { case list, calendar }

private func billingCycleLabel(_ cycle: BillingCycle) -> String {
    switch cycle {
    case .weekly:            return "Weekly"
    case .monthly:           return "Monthly"
    case .yearly:            return "Yearly"
    case .customDays(let n): return "Every \(n) days"
    }
}

struct SubscriptionsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SubscriptionsViewModel?
    @State private var inactiveSectionExpanded = false
    @State private var showError = false
    @State private var errorText = ""
    @State private var calendarMode: CalendarMode = .list
    @State private var calendarDisplayMonth: Date = {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }()

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    subscriptionsContent(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(String(localized: "Subscriptions"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let viewModel {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.presentAdd()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                        .accessibilityLabel(String(localized: "Add Subscription"))
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        Button {
                            viewModel.presentAutoDetect()
                        } label: {
                            Label(String(localized: "Scan"), systemImage: "doc.text.magnifyingglass")
                        }
                    }
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = SubscriptionsViewModel(context: modelContext)
            }
            viewModel?.refresh()
        }
        .sheet(item: destinationBinding) { destination in
            switch destination {
            case .add:
                SubscriptionFormSheet(mode: .add) { viewModel?.dismissDestination() }
            case .edit(let sub):
                SubscriptionFormSheet(mode: .edit(sub)) { viewModel?.dismissDestination() }
            case .autoDetect:
                AutoDetectSheet()
                    .onDisappear { viewModel?.dismissDestination() }
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
    }

    // MARK: - Content

    @ViewBuilder
    private func subscriptionsContent(_ viewModel: SubscriptionsViewModel) -> some View {
        if viewModel.subscriptions.isEmpty {
            emptyState(viewModel)
        } else {
            VStack(spacing: 0) {
                Picker(String(localized: "View"), selection: $calendarMode) {
                    Text(String(localized: "List")).tag(CalendarMode.list)
                    Text(String(localized: "Calendar")).tag(CalendarMode.calendar)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                if calendarMode == .list {
                    listContent(viewModel)
                } else {
                    SubscriptionsBillingCalendar(
                        activeSubscriptions: viewModel.activeSubscriptions,
                        homeCurrencyCode: viewModel.homeCurrencyCode,
                        displayMonth: $calendarDisplayMonth
                    )
                }
            }
        }
    }

    // MARK: - List content

    private func listContent(_ viewModel: SubscriptionsViewModel) -> some View {
        List {
            Section {
                monthlyCostCard(viewModel)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section(String(localized: "Active (\(viewModel.activeSubscriptions.count))")) {
                if viewModel.activeSubscriptions.isEmpty {
                    Text(String(localized: "No active subscriptions"))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(viewModel.activeSubscriptions, id: \.id) { sub in
                        subscriptionRow(sub, viewModel: viewModel)
                    }
                }
            }

            if !viewModel.inactiveSubscriptions.isEmpty {
                Section(isExpanded: $inactiveSectionExpanded) {
                    ForEach(viewModel.inactiveSubscriptions, id: \.id) { sub in
                        subscriptionRow(sub, viewModel: viewModel)
                    }
                } header: {
                    Button {
                        withAnimation { inactiveSectionExpanded.toggle() }
                    } label: {
                        HStack {
                            Text(String(localized: "Inactive"))
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: inactiveSectionExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
    }

    // MARK: - Monthly cost card

    private func monthlyCostCard(_ viewModel: SubscriptionsViewModel) -> some View {
        SummaryCard(
            title: String(localized: "Est. Monthly Cost"),
            icon: "calendar.circle.fill",
            amount: Money(minorUnits: viewModel.monthlyCostMinor, currencyCode: viewModel.homeCurrencyCode).formatted(),
            amountMinor: viewModel.monthlyCostMinor,
            isLoading: viewModel.monthlyCostIsLoading,
            subtitle: String(localized: "Active subscriptions only")
        )
    }

    // MARK: - Row

    private func subscriptionRow(_ sub: Subscription, viewModel: SubscriptionsViewModel) -> some View {
        SubscriptionRowView(
            subscription: sub,
            notificationsAuthorized: viewModel.notificationsAuthorized,
            homeAmountMinor: viewModel.subscriptionHomeAmounts[sub.id],
            homeCurrencyCode: viewModel.homeCurrencyCode
        )
        .contentShape(Rectangle())
        .onTapGesture { viewModel.presentEdit(sub) }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.deleteSubscription(sub)
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            switch sub.status {
            case .active:
                Button {
                    viewModel.pauseSubscription(sub)
                } label: {
                    Label(String(localized: "Pause"), systemImage: "pause.fill")
                }
                .tint(.orange)
            case .paused:
                Button {
                    viewModel.resumeSubscription(sub)
                } label: {
                    Label(String(localized: "Resume"), systemImage: "play.fill")
                }
                .tint(.green)
            case .cancelled:
                Button {
                    viewModel.resumeSubscription(sub)
                } label: {
                    Label(String(localized: "Restore"), systemImage: "arrow.uturn.left")
                }
                .tint(.blue)
            }
        }
    }

    // MARK: - Empty state

    private func emptyState(_ viewModel: SubscriptionsViewModel) -> some View {
        ContentUnavailableView {
            Label(String(localized: "No Subscriptions"), systemImage: "repeat.circle")
        } description: {
            Text(String(localized: "Add a subscription manually, or paste a billing email to detect it automatically."))
        } actions: {
            VStack(spacing: 10) {
                Button(String(localized: "Add Subscription")) {
                    viewModel.presentAdd()
                }
                .buttonStyle(.borderedProminent)
                Button(String(localized: "Scan from email or SMS")) {
                    viewModel.presentAutoDetect()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Sheet binding

    private var destinationBinding: Binding<SubscriptionsDestination?> {
        Binding(
            get: { viewModel?.destination },
            set: { viewModel?.destination = $0 }
        )
    }
}

// MARK: - Billing Calendar

private struct SubscriptionsBillingCalendar: View {
    let activeSubscriptions: [Subscription]
    let homeCurrencyCode: String
    @Binding var displayMonth: Date

    @State private var tappedDaySubscriptions: [Subscription] = []
    @State private var showDaySheet = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var cal: Calendar { Calendar.current }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                monthHeader
                weekdayLabels
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(0..<gridDays.count, id: \.self) { i in
                        if let day = gridDays[i] {
                            dayCell(day)
                        } else {
                            Color.clear.frame(height: 52)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
            .padding(.top, 4)
        }
        .sheet(isPresented: $showDaySheet) {
            BillingDaySheet(subscriptions: tappedDaySubscriptions, homeCurrencyCode: homeCurrencyCode)
        }
    }

    // MARK: Month header

    private var monthHeader: some View {
        HStack {
            Button {
                displayMonth = cal.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            Spacer()
            Text(displayMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button {
                displayMonth = cal.date(byAdding: .month, value: 1, to: displayMonth) ?? displayMonth
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Weekday labels

    private var weekdayLabels: some View {
        HStack(spacing: 0) {
            ForEach(shortWeekdaySymbols, id: \.self) { sym in
                Text(sym)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
    }

    private var shortWeekdaySymbols: [String] {
        let syms = cal.veryShortWeekdaySymbols
        let start = cal.firstWeekday - 1
        return Array(syms[start...] + syms[..<start])
    }

    // MARK: Grid data

    private var gridDays: [Date?] {
        let comps = cal.dateComponents([.year, .month], from: displayMonth)
        guard let monthStart = cal.date(from: comps),
              let nextMonth = cal.date(byAdding: .month, value: 1, to: monthStart),
              let daysInMonth = cal.dateComponents([.day], from: monthStart, to: nextMonth).day
        else { return [] }

        let firstWeekday = cal.component(.weekday, from: monthStart)
        let offset = (firstWeekday - cal.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: offset)
        for i in 0..<daysInMonth {
            days.append(cal.date(byAdding: .day, value: i, to: monthStart))
        }
        return days
    }

    private var billingsByDate: [Date: [Subscription]] {
        let monthComps = cal.dateComponents([.year, .month], from: displayMonth)
        var map: [Date: [Subscription]] = [:]
        for sub in activeSubscriptions {
            let billingDay = cal.startOfDay(for: sub.nextBillingDate)
            let bc = cal.dateComponents([.year, .month], from: billingDay)
            if bc.year == monthComps.year && bc.month == monthComps.month {
                map[billingDay, default: []].append(sub)
            }
        }
        return map
    }

    // MARK: Day cell

    private func dayCell(_ date: Date) -> some View {
        let isToday = cal.isDateInToday(date)
        let dayNumber = cal.component(.day, from: date)
        let billings = billingsByDate[date, default: []]

        return Button {
            guard !billings.isEmpty else { return }
            tappedDaySubscriptions = billings
            showDaySheet = true
        } label: {
            VStack(spacing: 3) {
                Text("\(dayNumber)")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(isToday ? .white : .primary)
                    .frame(width: 34, height: 34)
                    .background(isToday ? Color.accentColor : Color.clear)
                    .clipShape(Circle())

                if !billings.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(billings.prefix(3), id: \.id) { sub in
                            Circle()
                                .fill(Color(hex: sub.category?.colorHex ?? "#BDC3C7"))
                                .frame(width: 5, height: 5)
                        }
                    }
                } else {
                    Color.clear.frame(height: 5)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(!billings.isEmpty && !isToday
                          ? Color.accentColor.opacity(0.07)
                          : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            billings.isEmpty
                ? date.formatted(.dateTime.month().day())
                : String(localized: "\(date.formatted(.dateTime.month().day())), \(billings.count) billing")
        )
    }
}

// MARK: - Billing Day Sheet

private struct BillingDaySheet: View {
    @Environment(\.dismiss) private var dismiss
    let subscriptions: [Subscription]
    let homeCurrencyCode: String

    var body: some View {
        NavigationStack {
            List {
                ForEach(subscriptions, id: \.id) { sub in
                    HStack(spacing: 12) {
                        let hex = sub.category?.colorHex ?? "#BDC3C7"
                        let icon = sub.category?.iconName ?? "repeat.circle.fill"
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(hex: hex).opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: icon)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Color(hex: hex))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sub.name)
                                .font(.body)
                                .lineLimit(1)
                            Text(billingCycleLabel(sub.billingCycle))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(sub.money.formatted())
                            .font(.body)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(String(localized: "Billing on this day"))
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
    SubscriptionsView()
        .modelContainer(PreviewContainer.shared)
}
#endif
