import SwiftUI

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
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LedgerLiteDeepLink"))) { note in
                guard let url = note.object as? URL else { return }
                switch url.host {
                case "today", "expense": selectedTab = 0
                case "subscriptions":    selectedTab = 2
                case "insights":         selectedTab = 3
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
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && biometricLockEnabled {
                isLocked = true
            }
        }
    }
}

#Preview {
    ContentView()
}
