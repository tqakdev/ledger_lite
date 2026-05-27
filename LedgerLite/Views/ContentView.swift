import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem { Label(String(localized: "Today"), systemImage: "house") }
                .tag(0)

            SubscriptionsView()
                .tabItem { Label(String(localized: "Subscriptions"), systemImage: "repeat") }
                .tag(1)

            InsightsView()
                .tabItem { Label(String(localized: "Insights"), systemImage: "chart.pie") }
                .tag(2)

            SettingsView()
                .tabItem { Label(String(localized: "Settings"), systemImage: "gear") }
                .tag(3)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LedgerLiteDeepLink"))) { note in
            guard let url = note.object as? URL else { return }
            switch url.host {
            case "today", "expense": selectedTab = 0
            case "subscriptions":    selectedTab = 1
            default: break
            }
        }
    }
}

#Preview {
    ContentView()
}
