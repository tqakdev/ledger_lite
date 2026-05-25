import SwiftUI

// Phase 6: full Insights tab (period selector, donut chart, trend chart, budget progress).
struct InsightsView: View {
    var body: some View {
        NavigationStack {
            Text(String(localized: "Insights — Phase 6"))
                .foregroundStyle(.secondary)
                .navigationTitle(String(localized: "Insights"))
        }
    }
}

#Preview {
    InsightsView()
}
