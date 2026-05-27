import SwiftData

// Infrastructure for future iCloud sync (Phase 7.5).
// To enable: add CloudKit entitlements (requires paid Apple Developer account),
// then change cloudKitDatabase: .none → .private in LedgerLiteApp.makeContainer().

enum LedgerLiteSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Expense.self, Subscription.self, Category.self, ExchangeRateCache.self]
    }
}

enum LedgerLiteMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LedgerLiteSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
