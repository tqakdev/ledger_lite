import SwiftUI

// A2 + A10: chip styling, haptic, symmetric padding, scroll snapping
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
            // A10: allow chips to snap cleanly so they don't stop mid-chip
            .scrollTargetLayout()
            .padding(.horizontal)
        }
        .scrollTargetBehavior(.viewAligned)
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // A2: tertiarySystemFill for unselected (reads in both light/dark); 0.18 for selected
            .background(
                isSelected
                    ? Color(hex: category.colorHex).opacity(0.18)
                    : Color(.tertiarySystemFill)
            )
            .foregroundStyle(isSelected ? Color(hex: category.colorHex) : .primary)
            .clipShape(Capsule())
            // A2: separator border unselected (1 pt); full-alpha colour border selected (2 pt)
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color(hex: category.colorHex) : Color(.separator),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        // C2: full accessibility label with selection state
        .accessibilityLabel(String(localized: "\(category.name), \(isSelected ? "selected" : "not selected")"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
