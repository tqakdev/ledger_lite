import SwiftUI
import SwiftData
import SQLite3
import UserNotifications
import CoreSpotlight

@main
struct LedgerLiteApp: App {
    // Container created asynchronously so App.init() returns immediately and the
    // first frame renders before SwiftData opens the store.
    @State private var container: ModelContainer?

    init() {
        _ = MetricManager.shared
        UNUserNotificationCenter.current().delegate = AppNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    ContentView()
                        .modelContainer(container)
                        .task { await appDidLaunch(container: container) }
                        .onOpenURL { url in handleDeepLink(url) }
                        .onContinueUserActivity(CSSearchableItemActionType) { _ in
                            handleDeepLink(URL(string: "ledgerlite://today")!)
                        }
                } else {
                    Color(.systemBackground).ignoresSafeArea()
                }
            }
            .task {
                guard container == nil else { return }
                container = await Task.detached(priority: .userInitiated) {
                    Self.makeContainer()
                }.value
            }
        }
    }

    @MainActor
    private func handleDeepLink(_ url: URL) {
        AppLogger.ui.info("Deep link: \(url)")
        NotificationCenter.default.post(
            name: Notification.Name("LedgerLiteDeepLink"),
            object: url
        )
    }

    // MARK: - Private

    @MainActor
    private func appDidLaunch(container: ModelContainer) async {
        seedCategoriesIfNeeded(container: container)
        do {
            try await SubscriptionService(context: container.mainContext).generatePendingExpenses()
        } catch {
            AppLogger.subscriptions.error("Pending expense generation failed on launch: \(error)")
        }
    }

    @MainActor
    private func seedCategoriesIfNeeded(container: ModelContainer) {
        do {
            try CategoryRepository(context: container.mainContext).seedIfNeeded()
        } catch {
            AppLogger.data.error("Category seed failed: \(error)")
        }
    }

    /// Builds the ModelContainer using the App Group shared store URL so the widget
    /// extension can read the same SwiftData database.
    ///
    /// Falls back to the default sandbox location when the App Group container is
    /// unavailable (Simulator without a provisioning profile, CI builds).
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            Expense.self,
            Subscription.self,
            Category.self,
            ExchangeRateCache.self,
        ])

        if let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Constants.App.appGroupIdentifier) {
            let storeURL = groupURL.appendingPathComponent("LedgerLite.store")
            Self.enableWAL(at: storeURL)
            let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, migrationPlan: LedgerLiteMigrationPlan.self, configurations: [config])
            } catch {
                AppLogger.data.error("ModelContainer (App Group) init failed: \(error)")
            }
        } else {
            AppLogger.data.warning("App Group container unavailable — using default store.")
        }

        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, migrationPlan: LedgerLiteMigrationPlan.self, configurations: [config])
        } catch {
            fatalError("ModelContainer init failed entirely: \(error)")
        }
    }

    private static func enableWAL(at url: URL) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
    }
}
