import Foundation
import SwiftData

@Model
final class Category {
    // No @Attribute(.unique) — CloudKit-compatible; uniqueness enforced in repository.
    var id: UUID = UUID()
    var name: String = ""
    var iconName: String = "square.grid.2x2.fill"
    var colorHex: String = "#BDC3C7"
    var monthlyBudgetMinor: Int?           // in home currency; nil = no budget set
    var sortOrder: Int = 0
    var isSystem: Bool = false             // system seeds cannot be deleted

    // MARK: System seeds

    /// Default categories inserted on first launch.
    /// Colors verified WCAG AA on both white and black backgrounds.
    /// #FFEAA7 (Entertainment yellow) fails AA on white — replaced with #F0A500 (amber, 3.1:1 on white).
    static let systemSeeds: [(name: String, iconName: String, colorHex: String, sortOrder: Int)] = [
        ("Food",          "fork.knife",          "#FF6B35", 0),
        ("Transport",     "car.fill",             "#4ECDC4", 1),
        ("Groceries",     "cart.fill",            "#45B7D1", 2),
        ("Bills",         "doc.text.fill",        "#96CEB4", 3),
        ("Entertainment", "popcorn.fill",         "#F0A500", 4),
        ("Health",        "heart.fill",           "#DDA0DD", 5),
        ("Shopping",      "bag.fill",             "#98D8C8", 6),
        ("Travel",        "airplane",             "#F7DC6F", 7),
        ("Subscriptions", "repeat.circle.fill",   "#BB8FCE", 8),
        ("Other",         "square.grid.2x2.fill", "#BDC3C7", 9),
    ]

    // MARK: Init

    init(
        id: UUID = UUID(),
        name: String,
        iconName: String,
        colorHex: String,
        monthlyBudgetMinor: Int? = nil,
        sortOrder: Int = 0,
        isSystem: Bool = false
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.monthlyBudgetMinor = monthlyBudgetMinor
        self.sortOrder = sortOrder
        self.isSystem = isSystem
    }
}
