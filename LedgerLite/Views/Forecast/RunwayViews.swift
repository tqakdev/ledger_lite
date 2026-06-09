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
    else                 { body = String(format: "%.0f", abs) }
    return "\(sign)\(symbol)\(body)"
}

// MARK: - Setup prompt

/// Call-to-action shown on the Runway home before the user has entered a balance + payday.
struct RunwaySetupPromptView: View {
    let onSetup: () -> Void

    var body: some View {
        Button(action: onSetup) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    Text(String(localized: "Set up your runway"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(String(localized: "Add your available balance and next payday to see a daily safe-to-spend that already accounts for the bills heading your way — calculated entirely on your device."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
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

// MARK: - Inline forecast

/// The forward projection rendered inline on the Runway home: the headline
/// "truly safe to spend" figure, a live today-envelope bar, a what-if simulator,
/// the balance-to-payday curve with bill markers, and the list of bills before payday.
struct RunwayForecastView: View {
    let result: RunwayForecast.Result
    let currencyCode: String
    /// The inputs last used to compute `result` — nil-safe; what-if is hidden when nil.
    let lastInput: RunwayForecast.Input?
    /// How much has been spent today (home currency minor units), for the envelope bar.
    let todayTotalMinor: Int

    @State private var showWhatIf = false
    @State private var whatIfText = ""
    @State private var whatIfResult: RunwayForecast.Result? = nil

    private var danger: Bool { result.firstNegativeDate != nil }
    private var parser: AmountInputParser { AmountInputParser(currencyCode: currencyCode, locale: .current) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                headline
                envelopeBar
                whatIfSection
            }
            chart
            if !result.upcomingBills.isEmpty { billsList }
            explainer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            #if DEBUG
            applyScreenshotWhatIf()
            #endif
        }
    }

    // MARK: Headline

    private var headline: some View {
        let tint: Color = danger ? Theme.danger : Theme.positive
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
                .foregroundStyle(Theme.danger)
            } else {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        if result.totalUpcomingBillsMinor > 0 {
            let bills = Money(minorUnits: result.totalUpcomingBillsMinor, currencyCode: currencyCode).formatted()
            return String(localized: "After \(bills) in bills · \(result.daysToPayday) days to payday")
        }
        return String(localized: "\(result.daysToPayday) days until payday")
    }

    // MARK: Today envelope bar

    /// Live progress bar: shows how much of today's safe-to-spend has been consumed.
    /// Updates immediately as the user logs expenses — transforms the number from a
    /// static fact into a live decision aid.
    @ViewBuilder
    private var envelopeBar: some View {
        let safe = max(1, result.trulySafePerDayMinor)
        let spent = todayTotalMinor
        let remaining = safe - spent
        let fraction = min(1.0, max(0.0, Double(spent) / Double(safe)))
        let barTint: Color = fraction < 0.75 ? Theme.positive : fraction < 1.0 ? Theme.caution : Theme.danger

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(String(localized: "Today"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if remaining >= 0 {
                    Text(String(localized: "\(Money(minorUnits: remaining, currencyCode: currencyCode).formatted()) left today"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(barTint)
                } else {
                    Text(String(localized: "\(Money(minorUnits: abs(remaining), currencyCode: currencyCode).formatted()) over today"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.danger)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 7)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barTint)
                        .frame(width: geo.size.width * fraction, height: 7)
                        .animation(.spring(duration: 0.4), value: fraction)
                }
            }
            .frame(height: 7)
        }
        .contentTransition(.numericText())
        .animation(.easeInOut(duration: 0.3), value: todayTotalMinor)
    }

    // MARK: What-if simulator

    /// Interactive: "What if I spend $X?" — re-runs the forecast engine with the
    /// entered purchase subtracted and shows the new safe-to-spend and zero-date.
    @ViewBuilder
    private var whatIfSection: some View {
        if lastInput != nil {
            VStack(alignment: .leading, spacing: 8) {
                if !showWhatIf {
                    Button {
                        withAnimation(.spring(duration: 0.3)) { showWhatIf = true }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "questionmark.circle")
                                .font(.caption)
                            Text(String(localized: "What if I spend...?"))
                                .font(.caption)
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text(Money.symbol(for: currencyCode))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextField(String(localized: "Amount"), text: $whatIfText)
                                .keyboardType(.decimalPad)
                                .font(.subheadline.monospacedDigit())
                                .onChange(of: whatIfText) { _, v in
                                    let parsed = parser.parse(v)
                                    whatIfText = parsed.display
                                    applyWhatIf(minorUnits: parsed.minorUnits)
                                }
                            Spacer()
                            Button {
                                withAnimation(.spring(duration: 0.3)) {
                                    showWhatIf = false
                                    whatIfText = ""
                                    whatIfResult = nil
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        if let wir = whatIfResult {
                            whatIfOutcome(wir)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    #if DEBUG
    /// Opens the what-if simulator pre-filled for App Store screenshots: `--whatif 150`.
    private func applyScreenshotWhatIf() {
        guard !showWhatIf, lastInput != nil else { return }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--whatif"), i + 1 < args.count,
              let major = Double(args[i + 1]) else { return }
        let minor = Int((major * pow(10.0, Double(Money.decimals(for: currencyCode)))).rounded())
        showWhatIf = true
        whatIfText = parser.parse(String(Int(major))).display
        applyWhatIf(minorUnits: minor)
    }
    #endif

    private func applyWhatIf(minorUnits: Int) {
        guard minorUnits > 0, let input = lastInput else { whatIfResult = nil; return }
        let modified = RunwayForecast.Input(
            startingBalanceMinor: input.startingBalanceMinor - minorUnits,
            today: input.today,
            payday: input.payday,
            bills: input.bills,
            projectedDailyDiscretionaryMinor: input.projectedDailyDiscretionaryMinor
        )
        whatIfResult = RunwayForecast.project(modified)
    }

    @ViewBuilder
    private func whatIfOutcome(_ wir: RunwayForecast.Result) -> some View {
        let safeAfter = wir.trulySafePerDayMinor
        let safeBefore = result.trulySafePerDayMinor
        let newNegDate = wir.firstNegativeDate
        let wasNeg = result.firstNegativeDate != nil
        let nowNeg = newNegDate != nil

        let safePositive = safeAfter > 0
        let icon = safePositive && !nowNeg ? "checkmark.circle.fill"
            : (safePositive ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
        let tint: Color = safePositive && !nowNeg ? Theme.positive
            : (safePositive ? Theme.caution : Theme.danger)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(String(localized: "Safe to spend: \(Money(minorUnits: max(0, safeAfter), currencyCode: currencyCode).formatted())/day"))
                    .font(.subheadline.weight(.medium))
            }
            if safeBefore != safeAfter {
                let delta = abs(safeAfter - safeBefore)
                Text(safeAfter < safeBefore
                     ? String(localized: "↓ \(Money(minorUnits: delta, currencyCode: currencyCode).formatted())/day less than now")
                     : String(localized: "↑ \(Money(minorUnits: delta, currencyCode: currencyCode).formatted())/day more than now"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if nowNeg, !wasNeg, let neg = newNegDate {
                Text(String(localized: "⚠ You'd run out around \(neg.formatted(.dateTime.month(.abbreviated).day()))"))
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            } else if !nowNeg {
                Text(String(localized: "✓ You'd still make it to payday"))
                    .font(.caption)
                    .foregroundStyle(Theme.positive)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Chart

    private var chart: some View {
        let places = Money.decimals(for: currencyCode)
        let divisor = pow(10.0, Double(places))
        let tint: Color = danger ? Theme.danger : Theme.positive

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
                .foregroundStyle(Theme.danger.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

            // Bill markers.
            ForEach(result.upcomingBills) { bill in
                PointMark(
                    x: .value(String(localized: "Date"), bill.date),
                    y: .value(String(localized: "Balance"), billBalance(on: bill.date, divisor: divisor))
                )
                .symbol(.circle)
                .symbolSize(60)
                .foregroundStyle(Theme.caution)
                .annotation(position: .top, spacing: 2) {
                    Text(compactMoney(bill.amountMinor, currency: currencyCode))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Theme.caution)
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
                        .foregroundStyle(Theme.caution)
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
        .card()
    }

    // MARK: Explainer

    private var explainer: some View {
        Text(String(localized: "Projected from your upcoming bills and recent spending pace. Calculated entirely on your device — no bank connection."))
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
