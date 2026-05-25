import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label(String(localized: "Today"), systemImage: "house") }

            SubscriptionsView()
                .tabItem { Label(String(localized: "Subscriptions"), systemImage: "repeat") }

            InsightsView()
                .tabItem { Label(String(localized: "Insights"), systemImage: "chart.pie") }

            SettingsView()
                .tabItem { Label(String(localized: "Settings"), systemImage: "gear") }
        }
    }
}

#Preview {
    ContentView()
}
