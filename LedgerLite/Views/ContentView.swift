import SwiftUI

// MARK: - Shared summary card used across the Runway, Spending, and Bills tabs

struct SummaryCard<Supplement: View>: View {
    let title: String
    let icon: String?
    let money: Money
    let isLoading: Bool
    let subtitle: String
    @ViewBuilder let supplement: () -> Supplement

    init(
        title: String,
        icon: String? = nil,
        money: Money,
        isLoading: Bool = false,
        subtitle: String,
        @ViewBuilder supplement: @escaping () -> Supplement
    ) {
        self.title = title
        self.icon = icon
        self.money = money
        self.isLoading = isLoading
        self.subtitle = subtitle
        self.supplement = supplement
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(Theme.brand)
                        .font(.subheadline.weight(.medium))
                }
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if isLoading {
                ProgressView().frame(height: 44)
            } else {
                amountText
                    .contentTransition(.numericText(value: Double(money.minorUnits)))
                    .animation(.spring(duration: 0.4, bounce: 0.3), value: money.minorUnits)
            }
            supplement()
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
    }

    private var amountText: Text {
        let sym = Money.symbol(for: money.currencyCode)
        let full = money.formatted()
        let numStr = full.replacingOccurrences(of: sym, with: "").trimmingCharacters(in: .whitespaces)
        let symText = Text(sym).font(.system(.title2, design: .rounded, weight: .bold))
        let numText = Text(numStr).font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
        return full.hasPrefix(sym) ? symText + numText : numText + Text(" ") + symText
    }

}

extension SummaryCard where Supplement == EmptyView {
    init(title: String, icon: String? = nil, money: Money, isLoading: Bool = false, subtitle: String) {
        self.init(title: title, icon: icon, money: money, isLoading: isLoading, subtitle: subtitle, supplement: { EmptyView() })
    }
}

/// Deep-link requests that target a view the lazy TabView may not have built yet.
/// `ledgerlite://scan` switches to the Runway tab and posts a notification, but a
/// never-visited RunwayView has no subscriber at post time — the flag survives until
/// its `onAppear` consumes it.
enum PendingDeepLink {
    static var scanRequested = false
}

struct ContentView: View {
    @State private var selectedTab: Int = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("biometricLockEnabled") private var biometricLockEnabled = false
    @State private var isLocked = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                RunwayView()
                    .tabItem { Label(String(localized: "Runway"), systemImage: "chart.line.uptrend.xyaxis") }
                    .tag(0)

                HistoryView()
                    .tabItem { Label(String(localized: "Spending"), systemImage: "list.bullet") }
                    .tag(1)

                SubscriptionsView()
                    .tabItem { Label(String(localized: "Bills"), systemImage: "creditcard") }
                    .tag(2)

                SettingsView()
                    .tabItem { Label(String(localized: "Settings"), systemImage: "gear") }
                    .tag(3)
            }
            .onChange(of: selectedTab) { _, _ in
                UISelectionFeedbackGenerator().selectionChanged()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LedgerLiteDeepLink"))) { note in
                guard let url = note.object as? URL else { return }
                switch url.host {
                case "today", "runway":
                    selectedTab = 0
                // Trends lives inside the Spending tab now, and the widget's per-expense
                // links open the spending log.
                case "history", "spending", "expense", "insights", "trends":
                    selectedTab = 1
                case "subscriptions", "bills":
                    selectedTab = 2
                case "settings":
                    selectedTab = 3
                case "scan":
                    if selectedTab == 0 {
                        // Runway is visible — its onReceive can present immediately.
                        NotificationCenter.default.post(name: Notification.Name("LedgerLitePresentScan"), object: nil)
                    } else {
                        // Runway is hidden (or never built): posting now would reach a view
                        // that can't present a sheet. Park the request; RunwayView.onAppear
                        // consumes it right after the tab switch.
                        PendingDeepLink.scanRequested = true
                        selectedTab = 0
                    }
                default: break
                }
            }

            if isLocked {
                LockScreenView { isLocked = false }
                    .transition(.opacity)
                    .zIndex(1)
            } else if biometricLockEnabled && scenePhase != .active {
                // The app-switcher snapshot is taken while the scene is inactive — cover
                // balances and expenses before it happens. (.background alone is too late;
                // the lock itself only engages there.)
                PrivacyCoverView()
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )) {
            OnboardingView()
        }
        .onAppear {
            if biometricLockEnabled { isLocked = true }
            #if DEBUG
            applyLaunchScreen()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && biometricLockEnabled {
                isLocked = true
            }
        }
    }

    #if DEBUG
    /// Opens directly to a tab (or the scanner) when launched with
    /// `--screen <runway|spending|bills|settings|scan>` — used to capture App Store
    /// screenshots without taps or deep-link prompts. Legacy names still map.
    private func applyLaunchScreen() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--screen"), i + 1 < args.count else { return }
        switch args[i + 1] {
        case "spending", "history":          selectedTab = 1
        case "bills", "subscriptions":       selectedTab = 2
        case "insights", "trends":           selectedTab = 1
        case "settings":                     selectedTab = 3
        case "scan":
            selectedTab = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                NotificationCenter.default.post(name: Notification.Name("LedgerLitePresentScan"), object: nil)
            }
        default:                             selectedTab = 0   // runway / today
        }
    }
    #endif
}

#Preview {
    ContentView()
}
