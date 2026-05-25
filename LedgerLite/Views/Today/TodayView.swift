import SwiftUI

// Phase 3: full Today tab implementation (expense list, Quick Add sheet, numpad).
struct TodayView: View {
    var body: some View {
        NavigationStack {
            Text(String(localized: "Today — Phase 3"))
                .foregroundStyle(.secondary)
                .navigationTitle(String(localized: "Today"))
        }
    }
}

#Preview {
    TodayView()
}
