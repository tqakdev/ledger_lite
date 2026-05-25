import SwiftUI

// Phase 1 adds: import SwiftData + ModelContainer initialisation using the
// App Group shared store URL so the widget can read the same database.

@main
struct LedgerLiteApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
