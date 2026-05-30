import SwiftUI

// MARK: - Shared summary card used across Today, History, and Subscriptions tabs

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
                        .foregroundStyle(Color.accentColor)
                        .font(.subheadline)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), Color(.secondarySystemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
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

struct ContentView: View {
    @State private var selectedTab: Int = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("biometricLockEnabled") private var biometricLockEnabled = false
    @State private var isLocked = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                TodayView()
                    .tabItem { Label(String(localized: "Today"), systemImage: "house") }
                    .tag(0)

                HistoryView()
                    .tabItem { Label(String(localized: "History"), systemImage: "clock") }
                    .tag(1)

                SubscriptionsView()
                    .tabItem { Label(String(localized: "Subscriptions"), systemImage: "repeat") }
                    .tag(2)

                InsightsView()
                    .tabItem { Label(String(localized: "Insights"), systemImage: "chart.pie") }
                    .tag(3)

                SettingsView()
                    .tabItem { Label(String(localized: "Settings"), systemImage: "gear") }
                    .tag(4)
            }
            .onChange(of: selectedTab) { _, _ in
                UISelectionFeedbackGenerator().selectionChanged()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LedgerLiteDeepLink"))) { note in
                guard let url = note.object as? URL else { return }
                switch url.host {
                case "today", "expense": selectedTab = 0
                case "history":          selectedTab = 1
                case "subscriptions":    selectedTab = 2
                case "insights":         selectedTab = 3
                case "settings":         selectedTab = 4
                case "scan":
                    selectedTab = 0
                    NotificationCenter.default.post(name: Notification.Name("LedgerLitePresentScan"), object: nil)
                default: break
                }
            }

            if isLocked {
                LockScreenView { isLocked = false }
                    .transition(.opacity)
                    .zIndex(1)
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
    /// `--screen <today|history|subscriptions|insights|settings|scan>` — used to
    /// capture App Store screenshots without taps or deep-link prompts.
    private func applyLaunchScreen() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--screen"), i + 1 < args.count else { return }
        switch args[i + 1] {
        case "history":       selectedTab = 1
        case "subscriptions": selectedTab = 2
        case "insights":      selectedTab = 3
        case "settings":      selectedTab = 4
        case "scan":
            selectedTab = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                NotificationCenter.default.post(name: Notification.Name("LedgerLitePresentScan"), object: nil)
            }
        default:              selectedTab = 0
        }
    }
    #endif
}

#Preview {
    ContentView()
}
