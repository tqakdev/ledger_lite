import SwiftUI
import SwiftData
import SQLite3
import UserNotifications
import CoreSpotlight

@main
struct LedgerLiteApp: App {
    private let container: ModelContainer

    init() {
        _ = MetricManager.shared   // register MetricKit subscriber before first scene activates
        UNUserNotificationCenter.current().delegate = AppNotificationDelegate.shared
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { await appDidLaunch() }
                .onOpenURL { url in handleDeepLink(url) }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    // Spotlight tap — route to Today tab so the user can find the expense
                    handleDeepLink(URL(string: "ledgerlite://today")!)
                }
        }
        .modelContainer(container)
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
    private func appDidLaunch() async {
        seedCategoriesIfNeeded()
        do {
            try await SubscriptionService(context: container.mainContext).generatePendingExpenses()
        } catch {
            AppLogger.subscriptions.error("Pending expense generation failed on launch: \(error)")
        }
    }

    @MainActor
    private func seedCategoriesIfNeeded() {
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

        // Migration plan ensures future CloudKit / schema migrations are non-destructive.
        // To enable iCloud sync: add CloudKit entitlements (paid Apple Developer account required),
        // then change cloudKitDatabase: .none → .private below.
        if let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Constants.App.appGroupIdentifier) {
            let storeURL = groupURL.appendingPathComponent("LedgerLite.store")
            Self.enableWAL(at: storeURL)
            let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, migrationPlan: LedgerLiteMigrationPlan.self, configurations: [config])
            } catch {
                AppLogger.data.error("ModelContainer (App Group) init failed: \(error)")
                // Fall through to default location
            }
        } else {
            AppLogger.data.warning("App Group container unavailable — using default store. Register \(Constants.App.appGroupIdentifier) in the Developer Portal for widget data sharing.")
        }

        // Default location: works without provisioning, but widget can't access this store.
        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, migrationPlan: LedgerLiteMigrationPlan.self, configurations: [config])
        } catch {
            fatalError("ModelContainer init failed entirely: \(error)")
        }
    }

    /// Sets WAL journal mode before SwiftData opens the store, eliminating the
    /// "not configured in WAL mode" I/O warning from the SQLite subsystem.
    private static func enableWAL(at url: URL) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
    }
}
