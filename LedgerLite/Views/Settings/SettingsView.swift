import SwiftUI
import SwiftData
import LocalAuthentication

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    // B1: reactive home-currency display — shares App Group suite with UserPreferences + widget
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

    // B4: notification state
    @State private var notificationsAuthorized = false
    @State private var showCannotDisableAlert  = false
    @State private var showDeniedAlert         = false

    // B5: CSV export
    @State private var isExporting   = false
    @State private var csvExportURL: URL?

    // C3: error alert
    @State private var showError = false
    @State private var errorText = ""

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
        // B5: share sheet
        .sheet(isPresented: Binding(
            get: { csvExportURL != nil },
            set: { if !$0 { csvExportURL = nil } }
        )) {
            if let url = csvExportURL {
                ActivitySheet(url: url)
            }
        }
        // C3: generic error
        .alert(String(localized: "Something went wrong"), isPresented: $showError) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: { Text(errorText) }
        // B4: "can't disable in-app" alert
        .alert(String(localized: "Disable in System Settings"), isPresented: $showCannotDisableAlert) {
            Button(String(localized: "Open Settings")) {
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Go to Settings → Notifications → LedgerLite to turn off billing reminders."))
        }
        .alert(String(localized: "Biometrics Unavailable"), isPresented: $showBiometricUnavailableAlert) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "Face ID or Touch ID is not set up on this device. Enable it in Settings → Face ID & Passcode."))
        }
        // B4: "permission denied" alert
        .alert(String(localized: "Notifications Denied"), isPresented: $showDeniedAlert) {
            Button(String(localized: "Open Settings")) {
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Allow notifications in Settings → Notifications → LedgerLite."))
        }
    }

    // MARK: - B1: General

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

    // MARK: - B2: Categories

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

    // MARK: - B3: Budgets

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

    // MARK: - B4: Notifications

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

    // MARK: - B5: Data

    @ViewBuilder
    private var dataSection: some View {
        Section(String(localized: "Data")) {
            Button {
                Task { await exportCSV() }
            } label: {
                HStack {
                    Label(String(localized: "Export CSV"), systemImage: "square.and.arrow.up")
                    if isExporting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isExporting)
        }
    }

    // MARK: - B6: About

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
            let expenses = try ExpenseRepository(context: modelContext).fetchAll()
            var lines = ["Date,Merchant,Category,Amount,Currency,HomeAmount,HomeCurrency"]
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withFullDate]
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
                lines.append("\(date),\(merchant),\(category),\(amount),\(currency),\(homeAmount),\(homeCurr)")
            }
            let csv = lines.joined(separator: "\n")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("LedgerLite_Expenses.csv")
            try csv.write(to: url, atomically: true, encoding: .utf8)
            csvExportURL = url
        } catch {
            errorText = error.localizedDescription
            showError  = true
            AppLogger.data.error("CSV export failed: \(error)")
        }
    }

    private func csvEscape(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: - B1: Home Currency Picker (private, pushed via NavigationLink)

private struct HomeCurrencyPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("homeCurrencyCode", store: UserDefaults(suiteName: Constants.App.appGroupIdentifier))
    private var selected = Constants.App.homeCurrencyDefault

    var body: some View {
        List(Constants.App.supportedCurrencies, id: \.self) { code in
            Button {
                selected = code
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

// MARK: - B5: UIActivityViewController wrapper

private struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#if DEBUG
#Preview {
    SettingsView()
        .modelContainer(PreviewContainer.shared)
}
#endif
