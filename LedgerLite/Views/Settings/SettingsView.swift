import SwiftUI
import SwiftData
import LocalAuthentication
import WidgetKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("homeCurrencyCode", store: UserDefaults(suiteName: Constants.App.appGroupIdentifier))
    private var homeCurrencyCode = Constants.App.homeCurrencyDefault

    // Biometric lock
    @AppStorage("biometricLockEnabled") private var biometricLockEnabled = false
    @State private var showBiometricUnavailableAlert = false
    private var biometricLabel: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID:  return String(localized: "Face ID Lock")
        case .touchID: return String(localized: "Touch ID Lock")
        default:       return String(localized: "Biometric Lock")
        }
    }

    @State private var notificationsAuthorized = false
    @State private var showCannotDisableAlert  = false
    @State private var showDeniedAlert         = false

    @State private var isExporting      = false
    @State private var exportItems: [Any] = []
    @State private var isImporting      = false
    @State private var showImportPicker = false
    @State private var importResultText: String?
    @State private var showImportResult = false

    @State private var showError = false
    @State private var errorText = ""

    // Reset data
    @State private var showResetConfirmation = false

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"]           as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                generalSection
                categoriesSection
                budgetsSection
                notificationsSection
                securitySection
                dataSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(String(localized: "Settings"))
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            notificationsAuthorized = await SubscriptionService(context: modelContext).notificationsAuthorized()
        }
        .sheet(isPresented: Binding(
            get: { !exportItems.isEmpty },
            set: { if !$0 { exportItems = [] } }
        )) {
            ActivitySheet(items: exportItems)
        }
        .alert(String(localized: "Something went wrong"), isPresented: $showError) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: { Text(errorText) }
        .alert(String(localized: "Disable in System Settings"), isPresented: $showCannotDisableAlert) {
            Button(String(localized: "Open Settings")) {
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Go to Settings → Notifications → LedgerLite to turn off billing reminders."))
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            guard let url = try? result.get().first else { return }
            Task { await importCSV(from: url) }
        }
        .alert(String(localized: "Import Complete"), isPresented: $showImportResult) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(importResultText ?? "")
        }
        .alert(String(localized: "Biometrics Unavailable"), isPresented: $showBiometricUnavailableAlert) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "Face ID or Touch ID is not set up on this device. Enable it in Settings → Face ID & Passcode."))
        }
        .alert(String(localized: "Notifications Denied"), isPresented: $showDeniedAlert) {
            Button(String(localized: "Open Settings")) {
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Allow notifications in Settings → Notifications → LedgerLite."))
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section(String(localized: "General")) {
            NavigationLink {
                HomeCurrencyPickerView()
            } label: {
                Label {
                    HStack {
                        Text(String(localized: "Home Currency"))
                        Spacer()
                        Text(homeCurrencyCode)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    settingsIcon("dollarsign.circle.fill", color: .green)
                }
            }
        }
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        Section(String(localized: "Categories")) {
            NavigationLink {
                CategoriesSettingsView()
            } label: {
                Label {
                    Text(String(localized: "Manage Categories"))
                } icon: {
                    settingsIcon("tag.fill", color: .blue)
                }
            }
        }
    }

    // MARK: - Budgets

    private var budgetsSection: some View {
        Section(String(localized: "Budgets")) {
            NavigationLink {
                BudgetsSettingsView()
            } label: {
                Label {
                    Text(String(localized: "Monthly Budgets"))
                } icon: {
                    settingsIcon("chart.bar.fill", color: .orange)
                }
            }
        }
    }

    private func settingsIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section(String(localized: "Notifications")) {
            Toggle(String(localized: "Billing Reminders"), isOn: Binding(
                get: { notificationsAuthorized },
                set: { newValue in
                    if newValue && !notificationsAuthorized {
                        Task { await requestNotifications() }
                    } else if !newValue && notificationsAuthorized {
                        showCannotDisableAlert = true
                    }
                }
            ))
            Text(notificationsAuthorized
                 ? String(localized: "Active — notified 2 days before each billing date.")
                 : String(localized: "Reminders are off."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Security

    private var securitySection: some View {
        Section(String(localized: "Security")) {
            Toggle(isOn: $biometricLockEnabled) {
                Label {
                    Text(biometricLabel)
                } icon: {
                    settingsIcon("faceid", color: .indigo)
                }
            }
            .onChange(of: biometricLockEnabled) { _, enabled in
                guard enabled else { return }
                let ctx = LAContext()
                var err: NSError?
                if !ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) {
                    biometricLockEnabled = false
                    showBiometricUnavailableAlert = true
                }
            }
            Text(biometricLockEnabled
                 ? String(localized: "App locks when sent to background.")
                 : String(localized: "Protect your data with Face ID or Touch ID."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data

    @ViewBuilder
    private var dataSection: some View {
        Section(String(localized: "Data")) {
            Button {
                Task { await exportCSV() }
            } label: {
                HStack {
                    Label(String(localized: "Export CSV"), systemImage: "square.and.arrow.up")
                    if isExporting { Spacer(); ProgressView() }
                }
            }
            .disabled(isExporting)

            Button {
                showImportPicker = true
            } label: {
                HStack {
                    Label(String(localized: "Import CSV"), systemImage: "square.and.arrow.down")
                    if isImporting { Spacer(); ProgressView() }
                }
            }
            .disabled(isImporting)

            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label(String(localized: "Reset All Data"), systemImage: "trash.fill")
            }
        }
        .confirmationDialog(
            String(localized: "Reset All Data"),
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete Everything"), role: .destructive) {
                Task { await resetAllData() }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This will permanently delete all expenses and subscriptions. This cannot be undone."))
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section(String(localized: "About")) {
            HStack {
                Text(String(localized: "Version"))
                Spacer()
                Button {
                    UIPasteboard.general.string = appVersion
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    HStack(spacing: 4) {
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Version \(appVersion), tap to copy"))

            Link(destination: URL(string: "https://bluemadisonblue.github.io/ledgerlite-privacy/")!) {
                HStack {
                    Text(String(localized: "Privacy Policy"))
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    // MARK: - Notification helpers

    private func requestNotifications() async {
        let granted = await SubscriptionService(context: modelContext).requestNotificationPermission()
        notificationsAuthorized = granted
        if !granted { showDeniedAlert = true }
    }

    // MARK: - CSV export

    private func exportCSV() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withFullDate]

            // Expenses
            let expenses = try ExpenseRepository(context: modelContext).fetchAll()
            var expenseLines = ["Date,Merchant,Category,Amount,Currency,HomeAmount,HomeCurrency"]
            for e in expenses {
                let date       = csvEscape(iso.string(from: e.date))
                let merchant   = csvEscape(e.merchant ?? "")
                let category   = csvEscape(e.category?.name ?? "")
                let amount     = e.money.decimalValue.description
                let currency   = e.currencyCode
                let homeAmount = (e.money.decimalValue * e.exchangeRateToHome)
                    .rounded(scale: Money.decimals(for: e.homeCurrencyAtEntry))
                    .description
                let homeCurr   = e.homeCurrencyAtEntry
                expenseLines.append("\(date),\(merchant),\(category),\(amount),\(currency),\(homeAmount),\(homeCurr)")
            }
            let expensesURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("LedgerLite_Expenses.csv")
            try expenseLines.joined(separator: "\n").write(to: expensesURL, atomically: true, encoding: .utf8)

            // Subscriptions
            let subscriptions = try SubscriptionRepository(context: modelContext).fetchAll()
            var subLines = ["Name,Amount,Currency,BillingCycle,NextBillingDate,Status"]
            for s in subscriptions {
                let name    = csvEscape(s.name)
                let amount  = s.money.decimalValue.description
                let cycle   = csvEscape(s.billingCycle.rawValue)
                let nextDate = csvEscape(iso.string(from: s.nextBillingDate))
                let status  = csvEscape(s.status.rawValue)
                subLines.append("\(name),\(amount),\(s.currencyCode),\(cycle),\(nextDate),\(status)")
            }
            let subscriptionsURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("LedgerLite_Subscriptions.csv")
            try subLines.joined(separator: "\n").write(to: subscriptionsURL, atomically: true, encoding: .utf8)

            exportItems = [expensesURL, subscriptionsURL]
        } catch {
            errorText = error.localizedDescription
            showError  = true
            AppLogger.data.error("CSV export failed: \(error)")
        }
    }

    private func csvEscape(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - CSV import

    private func importCSV(from url: URL) async {
        isImporting = true
        defer { isImporting = false }

        guard url.startAccessingSecurityScopedResource() else {
            errorText = String(localized: "Could not access the selected file.")
            showError = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
                .filter { !$0.isEmpty }
            guard lines.count > 1 else {
                importResultText = String(localized: "The file contains no expense rows.")
                showImportResult = true
                return
            }

            let categories = (try? CategoryRepository(context: modelContext).fetchAll()) ?? []
            var imported = 0

            for line in lines.dropFirst() {
                let fields = csvParseLine(line)
                guard fields.count >= 7 else { continue }
                let dateStr    = fields[0]
                let merchant   = fields[1].isEmpty ? nil : fields[1]
                let catName    = fields[2]
                let amtStr     = fields[3]
                let currency   = fields[4]
                let homeAmtStr = fields[5]
                let homeCurr   = fields[6]

                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withFullDate]
                guard let date = iso.date(from: dateStr) else { continue }
                guard let amtDecimal  = Decimal(string: amtStr),  amtDecimal  > 0 else { continue }
                guard let homeDecimal = Decimal(string: homeAmtStr) else { continue }

                let places     = Money.decimals(for: currency)
                let homePlaces = Money.decimals(for: homeCurr)

                func toMinor(_ d: Decimal, places p: Int) -> Int {
                    let v = (d * Decimal.powerOfTen(p)).rounded(scale: 0)
                    return NSDecimalNumber(decimal: v).intValue
                }

                let amtMinor  = toMinor(amtDecimal,  places: places)
                guard amtMinor > 0 else { continue }
                let homeMinor = toMinor(homeDecimal, places: homePlaces)
                let rate: Decimal = (currency == homeCurr || amtDecimal == Decimal(0))
                    ? Decimal(1) : (homeDecimal / amtDecimal)

                let category = categories.first { $0.name == catName }
                let expense  = Expense(
                    amountMinor: amtMinor,
                    currencyCode: currency,
                    exchangeRateToHome: rate,
                    homeCurrencyAtEntry: homeCurr,
                    date: date,
                    merchant: merchant,
                    source: .manual
                )
                expense.category = category
                _ = homeMinor  // stored in exchangeRateToHome; kept for future use
                modelContext.insert(expense)
                imported += 1
            }

            try modelContext.save()
            let plural = imported == 1
                ? String(localized: "Imported 1 expense.")
                : String(localized: "Imported \(imported) expenses.")
            importResultText = plural
            showImportResult = true
            AppLogger.data.info("CSV import: \(imported) expenses added")
        } catch {
            errorText = error.localizedDescription
            showError  = true
            AppLogger.data.error("CSV import failed: \(error)")
        }
    }

    private func csvParseLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if ch == "\"" {
                let next = line.index(after: i)
                if inQuotes && next < line.endIndex && line[next] == "\"" {
                    current.append("\"")
                    i = line.index(after: next)
                    continue
                }
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            i = line.index(after: i)
        }
        fields.append(current)
        return fields
    }

    // MARK: - Reset

    private func resetAllData() async {
        do {
            try modelContext.delete(model: Expense.self)
            try modelContext.delete(model: Subscription.self)
            try modelContext.save()
            let defaults = UserDefaults.standard
            defaults.dictionaryRepresentation().keys
                .filter { $0.hasPrefix("budgetAlert_") }
                .forEach { defaults.removeObject(forKey: $0) }
            importResultText = String(localized: "All data deleted.")
            showImportResult = true
            AppLogger.data.info("All data reset by user")
        } catch {
            errorText = error.localizedDescription
            showError = true
            AppLogger.data.error("Reset all data failed: \(error)")
        }
    }
}

// MARK: - Home Currency Picker

private struct HomeCurrencyPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("homeCurrencyCode", store: UserDefaults(suiteName: Constants.App.appGroupIdentifier))
    private var selected = Constants.App.homeCurrencyDefault

    var body: some View {
        List(Constants.App.supportedCurrencies, id: \.self) { code in
            Button {
                selected = code
                WidgetCenter.shared.reloadAllTimelines()
                // Background rate fetch — idempotent, failure is silent
                Task {
                    try? await CurrencyService(context: modelContext)
                        .ensureTodayRates(for: Constants.App.supportedCurrencies)
                }
            } label: {
                HStack {
                    Text(code).foregroundStyle(.primary)
                    Spacer()
                    if code == selected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                            .fontWeight(.semibold)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(String(localized: "Home Currency"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - UIActivityViewController wrapper

private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#if DEBUG
#Preview {
    SettingsView()
        .modelContainer(PreviewContainer.shared)
}
#endif
