import CoreSpotlight
import Foundation

struct SpotlightService {
    private static let domain = "com.enes.ledgerlite.expense"

    static func index(_ expense: Expense) {
        let attr = CSSearchableItemAttributeSet(contentType: .item)
        attr.displayName = expense.merchant ?? expense.category?.name ?? String(localized: "Expense")
        attr.contentDescription = "\(expense.money.formatted()) · \(expense.date.formatted(date: .abbreviated, time: .omitted))"
        if let cat = expense.category {
            attr.keywords = [cat.name]
        }
        let item = CSSearchableItem(
            uniqueIdentifier: "expense-\(expense.id.uuidString)",
            domainIdentifier: domain,
            attributeSet: attr
        )
        CSSearchableIndex.default().indexSearchableItems([item]) { _ in }
    }

    static func deindex(_ expenseID: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: ["expense-\(expenseID.uuidString)"]
        ) { _ in }
    }

    static func deindexAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in }
    }
}
