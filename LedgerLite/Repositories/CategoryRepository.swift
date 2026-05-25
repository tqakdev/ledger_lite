import Foundation
import SwiftData

// MARK: - RepositoryError

enum RepositoryError: Error, LocalizedError {
    case duplicateName(String)
    case cannotDeleteSystemCategory(String)

    var errorDescription: String? {
        switch self {
        case .duplicateName(let name):
            return String(localized: "A category named '\(name)' already exists.")
        case .cannotDeleteSystemCategory(let name):
            return String(localized: "'\(name)' is a built-in category and cannot be deleted.")
        }
    }
}

// MARK: - CategoryRepository

@MainActor
final class CategoryRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Inserts the 10 system seed categories if none exist yet. Safe to call on every launch.
    func seedIfNeeded() throws {
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.isSystem == true }
        )
        let existingCount = try context.fetchCount(descriptor)
        guard existingCount == 0 else { return }

        for seed in Category.systemSeeds {
            context.insert(Category(
                name: seed.name,
                iconName: seed.iconName,
                colorHex: seed.colorHex,
                sortOrder: seed.sortOrder,
                isSystem: true
            ))
        }
        try context.save()
        AppLogger.data.info("Seeded \(Category.systemSeeds.count) default categories")
    }

    func fetchAll() throws -> [Category] {
        try context.fetch(
            FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder)])
        )
    }

    /// Adds a new custom category. Throws if a category with the same name already exists.
    func add(name: String, iconName: String, colorHex: String, sortOrder: Int) throws -> Category {
        let lower = name.lowercased()
        let all = try context.fetch(FetchDescriptor<Category>())
        guard !all.contains(where: { $0.name.lowercased() == lower }) else {
            throw RepositoryError.duplicateName(name)
        }
        let category = Category(name: name, iconName: iconName, colorHex: colorHex, sortOrder: sortOrder)
        context.insert(category)
        try context.save()
        return category
    }

    /// Deletes a custom category. Throws if `isSystem == true`.
    func delete(_ category: Category) throws {
        guard !category.isSystem else {
            throw RepositoryError.cannotDeleteSystemCategory(category.name)
        }
        context.delete(category)
        try context.save()
    }
}
