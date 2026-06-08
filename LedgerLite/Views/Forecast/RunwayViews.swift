import SwiftUI
import Charts

// MARK: - Compact currency helper

/// Short money label for tight spaces (axis ticks, chips): "$1.2k", "-$340".
private func compactMoney(_ minor: Int, currency: String) -> String {
    let places = Money.decimals(for: currency)
    let major = Double(minor) / pow(10.0, Double(places))
    let symbol = Money.symbol(for: currency)
    let sign = major < 0 ? "-" : ""
    let abs = Swift.abs(major)
    let body: String
    if abs >= 1_000_000 { body = String(format: "%.1fM", abs / 1_000_000) }
    else if abs >= 1_000 { body = String(format: "%.1fk", abs / 1_000) }
    else if abs >= 100   { body = String(format: "%.0f", abs) }
    else                 { body = String(format: "%.0f", abs) }
    return "\(sign)\(symbol)\(body)"
}

// MARK: - Runway card (Today hero)

/// The forward-looking hero on the Today screen. Shows the single "truly safe to spend"
/// number, or a setup call-to-action when the user hasn't entered a balance + payday yet.
struct RunwayCardView: View {
    let result: RunwayForecast.Result?
    let hasSetup: Bool
    let currencyCode: String
    let onOpenDetail: () -> Void
    let onSetup: () -> Void

    var body: some View {
        if hasSetup, let result {
            configured(result)
        } else {
            setupPrompt
        }
    }

    // MARK: Configured state

    @ViewBuilder
    private func configured(_ result: RunwayForecast.Result) -> some View {
        let danger = result.firstNegativeDate != nil
        let tint: Color = danger ? .red : .mint

        Button(action: onOpenDetail) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: danger ? "exclamationmark.triangle.fill" : "chart.line.uptrend.xyaxis")
                        .font(.subheadline)
                        .foregroundStyle(tint)
                    Text(String(localized: "Runway to payday"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                Text(Money(minorUnits: result.trulySafePerDayMinor, currencyCode: currencyCode).formatted())
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                + Text(String(localized: " / day"))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(subtitle(result, danger: danger))
                    .font(.caption)
                    .foregroundStyle(danger ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.14), Color(.secondarySystemGroupedBackground)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(result, danger: danger))
        .accessibilityHint(String(localized: "Opens the runway forecast"))
    }

    private func subtitle(_ result: RunwayForecast.Result, danger: Bool) -> String {
        if danger, let neg = result.firstNegativeDate {
            return String(localized: "Heads up — projected to run out by \(neg.formatted(.dateTime.month(.abbreviated).day()))")
        }
        let bills = Money(minorUnits: result.totalUpcomingBillsMinor, currencyCode: currencyCode).formatted()
        if result.totalUpcomingBillsMinor > 0 {
            return String(localized: "Safe daily spend after \(bills) in upcoming bills · \(result.daysToPayday) days left")
        }
        return String(localized: "\(result.daysToPayday) days until payday")
    }

    private func accessibilityLabel(_ result: RunwayForecast.Result, danger: Bool) -> String {
        let amount = Money(minorUnits: result.trulySafePerDayMinor, currencyCode: currencyCode).formatted()
        if danger, let neg = result.firstNegativeDate {
            return String(localized: "Runway: safe to spend \(amount) per day. Warning: projected to run out by \(neg.formatted(.dateTime.month(.abbreviated).day())).")
        }
        return String(localized: "Runway: safe to spend \(amount) per day for \(result.daysToPayday) days until payday.")
    }

    // MARK: Setup prompt

    private var setupPrompt: some View {
        Button(action: onSetup) {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "See your runway to payday"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(String(localized: "Add your balance and payday to get a daily safe-to-spend that accounts for upcoming bills."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.accentColor.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Runway detail

/// Full forward projection: the balance curve from today to payday with bill markers,
/// a zero "danger line", and the list of bills due before payday.
struct RunwayDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let result: RunwayForecast.Result
    let currencyCode: String
    let onEdit: () -> Void

    private var danger: Bool { result.firstNegativeDate != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headline
                    chart
                    if !result.upcomingBills.isEmpty { billsList }
                    explainer
                }
                .padding()
            }
            .navigationTitle(String(localized: "Runway"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Edit")) { onEdit() }
                }
            }
        }
    }

    // MARK: Headline

    private var headline: some View {
        let tint: Color = danger ? .red : .mint
        return VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Truly safe to spend"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Money(minorUnits: result.trulySafePerDayMinor, currencyCode: currencyCode).formatted())
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text(String(localized: "/ day"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if danger, let neg = result.firstNegativeDate {
                Label(
                    String(localized: "At your current pace, you run out around \(neg.formatted(.dateTime.month(.abbreviated).day()))."),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Chart

    private var chart: some View {
        let places = Money.decimals(for: currencyCode)
        let divisor = pow(10.0, Double(places))
        let tint: Color = danger ? .red : .mint

        return Chart {
            ForEach(result.dailyBalances, id: \.date) { point in
                AreaMark(
                    x: .value(String(localized: "Date"), point.date),
                    y: .value(String(localized: "Balance"), Double(point.balanceMinor) / divisor)
                )
                .foregroundStyle(
                    LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.05)],
                                   startPoint: .top, endPoint: .bottom)
                )
                LineMark(
                    x: .value(String(localized: "Date"), point.date),
                    y: .value(String(localized: "Balance"), Double(point.balanceMinor) / divisor)
                )
                .foregroundStyle(tint)
                .interpolationMethod(.monotone)
            }

            // Zero "danger line".
            RuleMark(y: .value(String(localized: "Zero"), 0.0))
                .foregroundStyle(.red.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

            // Bill markers.
            ForEach(result.upcomingBills) { bill in
                PointMark(
                    x: .value(String(localized: "Date"), bill.date),
                    y: .value(String(localized: "Balance"), billBalance(on: bill.date, divisor: divisor))
                )
                .symbol(.circle)
                .symbolSize(60)
                .foregroundStyle(Color.orange)
                .annotation(position: .top, spacing: 2) {
                    Text(compactMoney(bill.amountMinor, currency: currencyCode))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let major = value.as(Double.self) {
                        Text(compactMoney(Int(major * divisor), currency: currencyCode))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 200)
    }

    /// The projected balance on a bill's day, for placing its marker on the curve.
    private func billBalance(on date: Date, divisor: Double) -> Double {
        let cal = Calendar.current
        let match = result.dailyBalances.first { cal.isDate($0.date, inSameDayAs: date) }
        return Double(match?.balanceMinor ?? 0) / divisor
    }

    // MARK: Bills list

    private var billsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Bills before payday"))
                .font(.headline)
            ForEach(result.upcomingBills) { bill in
                HStack {
                    Image(systemName: "repeat.circle.fill")
                        .foregroundStyle(.orange)
                    Text(bill.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Money(minorUnits: bill.amountMinor, currencyCode: currencyCode).formatted())
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                        Text(bill.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            Divider()
            HStack {
                Text(String(localized: "Total committed"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Money(minorUnits: result.totalUpcomingBillsMinor, currencyCode: currencyCode).formatted())
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Explainer

    private var explainer: some View {
        Text(String(localized: "Your runway projects your balance forward using your upcoming subscription bills and your recent spending pace. Everything is calculated on your device — no bank connection."))
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Setup sheet

/// Captures the only data the runway needs that the app doesn't already have:
/// current available balance and the next payday.
struct RunwaySetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currencyCode: String
    let isConfigured: Bool
    let onSave: (_ balanceMinor: Int, _ payday: Date) -> Void
    let onClear: () -> Void

    @State private var amountText: String = ""
    @State private var payday: Date

    init(
        currencyCode: String,
        isConfigured: Bool,
        initialBalanceMinor: Int?,
        initialPayday: Date?,
        onSave: @escaping (_ balanceMinor: Int, _ payday: Date) -> Void,
        onClear: @escaping () -> Void
    ) {
        self.currencyCode = currencyCode
        self.isConfigured = isConfigured
        self.onSave = onSave
        self.onClear = onClear
        let parser = AmountInputParser(currencyCode: currencyCode, locale: .current)
        _amountText = State(initialValue: initialBalanceMinor.map { parser.format(minorUnits: $0) } ?? "")
        _payday = State(initialValue: initialPayday ?? Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date())
    }

    private var parser: AmountInputParser { AmountInputParser(currencyCode: currencyCode, locale: .current) }
    private var minorUnits: Int { parser.parse(amountText).minorUnits }
    private var canSave: Bool { minorUnits > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(Money.symbol(for: currencyCode))
                            .foregroundStyle(.secondary)
                        TextField(String(localized: "Available balance"), text: $amountText)
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                            .onChange(of: amountText) { _, newValue in
                                amountText = parser.parse(newValue).display
                            }
                    }
                } header: {
                    Text(String(localized: "Current balance"))
                } footer: {
                    Text(String(localized: "What you have available to spend right now, in \(currencyCode). Expenses you log will be subtracted automatically."))
                }

                Section {
                    DatePicker(
                        String(localized: "Next payday"),
                        selection: $payday,
                        in: Date()...,
                        displayedComponents: .date
                    )
                } footer: {
                    Text(String(localized: "The runway projects your balance forward to this date."))
                }

                if isConfigured {
                    Section {
                        Button(role: .destructive) {
                            onClear()
                            dismiss()
                        } label: {
                            Text(String(localized: "Turn off runway"))
                        }
                    }
                }
            }
            .navigationTitle(isConfigured ? String(localized: "Edit Runway") : String(localized: "Set Up Runway"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        onSave(minorUnits, payday)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
