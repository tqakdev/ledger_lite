import SwiftUI

struct AmountNumpad: View {
    let decimalPlaces: Int
    let onDigit: (Int) -> Void
    let onDelete: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            numpadButton("1") { onDigit(1) }
            numpadButton("2") { onDigit(2) }
            numpadButton("3") { onDigit(3) }
            numpadButton("4") { onDigit(4) }
            numpadButton("5") { onDigit(5) }
            numpadButton("6") { onDigit(6) }
            numpadButton("7") { onDigit(7) }
            numpadButton("8") { onDigit(8) }
            numpadButton("9") { onDigit(9) }
            bottomLeftKey
            numpadButton("0") { onDigit(0) }
            Button(action: onDelete) {
                Image(systemName: "delete.backward.fill")
                    .font(.title2)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(String(localized: "Delete"))
        }
    }

    // TODO: Add a decimal-point key here for currencies where decimalPlaces > 0, with a hint
    // like "Enter cents" so users understand the numpad auto-shifts from major to minor units.
    private var bottomLeftKey: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 52)
            .accessibilityHidden(true)
    }

    private func numpadButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.title)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
    }
}

#Preview {
    AmountNumpad(decimalPlaces: 2, onDigit: { _ in }, onDelete: {})
        .padding()
}
