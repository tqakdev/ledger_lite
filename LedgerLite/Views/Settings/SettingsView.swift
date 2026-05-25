import SwiftUI

// Phase 7: full Settings tab (home currency, categories, notifications, export, appearance).
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Text(String(localized: "Settings — Phase 7"))
                .foregroundStyle(.secondary)
                .navigationTitle(String(localized: "Settings"))
        }
    }
}

#Preview {
    SettingsView()
}
