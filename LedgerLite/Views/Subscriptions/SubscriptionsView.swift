import SwiftUI

// Phase 4: full Subscriptions tab (list, true monthly cost card, add/edit/cancel).
struct SubscriptionsView: View {
    var body: some View {
        NavigationStack {
            Text(String(localized: "Subscriptions — Phase 4"))
                .foregroundStyle(.secondary)
                .navigationTitle(String(localized: "Subscriptions"))
        }
    }
}

#Preview {
    SubscriptionsView()
}
