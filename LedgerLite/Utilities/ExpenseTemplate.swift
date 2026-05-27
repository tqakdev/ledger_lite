import Foundation

struct ExpenseTemplate: Codable, Identifiable, Hashable {
    var id: UUID
    var merchantName: String
    var amountMinor: Int
    var currencyCode: String
    var categoryName: String
    var note: String

    init(
        id: UUID = UUID(),
        merchantName: String,
        amountMinor: Int,
        currencyCode: String,
        categoryName: String,
        note: String = ""
    ) {
        self.id = id
        self.merchantName = merchantName
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.categoryName = categoryName
        self.note = note
    }
}

enum ExpenseTemplateService {
    private static let key = "expenseTemplates"
    private static let maxCount = 8

    static func load() -> [ExpenseTemplate] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let templates = try? JSONDecoder().decode([ExpenseTemplate].self, from: data)
        else { return [] }
        return templates
    }

    static func save(_ templates: [ExpenseTemplate]) {
        guard let data = try? JSONEncoder().encode(Array(templates.prefix(maxCount))) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func add(_ template: ExpenseTemplate) {
        var all = load()
        all.removeAll {
            $0.merchantName == template.merchantName &&
            $0.amountMinor == template.amountMinor &&
            $0.currencyCode == template.currencyCode
        }
        all.insert(template, at: 0)
        save(all)
    }

    static func delete(id: UUID) {
        save(load().filter { $0.id != id })
    }
}
