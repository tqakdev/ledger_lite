import Foundation
import SwiftData

@MainActor
final class ExpenseRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchToday() throws -> [Expense] {
        let start = Date.now.startOfDay
        let end   = start.adding(days: 1)
        return try context.fetch(
            FetchDescriptor<Expense>(
                predicate: #Predicate { $0.date >= start && $0.date < end },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        )
    }

    func fetchAll() throws -> [Expense] {
        try context.fetch(
            FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        )
    }

    func add(_ expense: Expense) throws {
        context.insert(expense)
        try context.save()
    }

    func update(_ expense: Expense) throws {
        try context.save()
    }

    func delete(_ expense: Expense) throws {
        context.delete(expense)
        try context.save()
    }

    func fetchNeedingRateRefresh() throws -> [Expense] {
        try context.fetch(
            FetchDescriptor<Expense>(
                predicate: #Predicate { $0.needsRateRefresh == true },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        )
    }

    func savePendingChanges() throws {
        try context.save()
    }
}
