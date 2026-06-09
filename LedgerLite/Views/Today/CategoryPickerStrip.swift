import SwiftUI

struct CategoryPickerStrip: View {
    let categories: [Category]
    @Binding var selected: Category?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(categories, id: \.id) { category in
                    CategoryChip(
                        category: category,
                        isSelected: selected?.id == category.id
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selected = category
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
        .padding(.vertical, 4)
    }
}

private struct CategoryChip: View {
    let category: Category
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.iconName)
                    .font(.caption)
                Text(category.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                isSelected
                    ? Color(hex: category.colorHex).opacity(0.18)
                    : Color(.tertiarySystemFill)
            )
            .foregroundStyle(isSelected ? Color(hex: category.colorHex) : .primary)
            .clipShape(Capsule())
            .fixedSize(horizontal: false, vertical: true)
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color(hex: category.colorHex) : Color(.separator),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected
            ? String(localized: "\(category.name), selected")
            : String(localized: "\(category.name), not selected"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
