import Foundation
import SwiftData

@MainActor
final class SubscriptionRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchActive() throws -> [Subscription] {
        try context.fetch(
            FetchDescriptor<Subscription>(
                predicate: #Predicate { $0.statusRaw == "active" },
                sortBy: [SortDescriptor(\.nextBillingDate)]
            )
        )
    }

    func fetchAll() throws -> [Subscription] {
        try context.fetch(
            FetchDescriptor<Subscription>(sortBy: [SortDescriptor(\.nextBillingDate)])
        )
    }

    func add(_ subscription: Subscription) throws {
        context.insert(subscription)
        try context.save()
    }

    func delete(_ subscription: Subscription) throws {
        context.delete(subscription)
        try context.save()
    }
}
