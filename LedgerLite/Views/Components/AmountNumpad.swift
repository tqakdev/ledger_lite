import SwiftUI

/// A custom in-sheet numeric keypad for money entry, used in place of the system
/// `decimalPad`. Large tap targets, locale-aware decimal separator, and an optional
/// prominent save button. Shared by the expense and subscription entry sheets.
///
/// All input is funneled through the caller's `onDigit` / `onSeparator` / `onBackspace`
/// closures, which typically mutate the view model's `amountString` via `setAmount`.
struct AmountNumpad: View {
    let separator: String
    let allowsDecimal: Bool
    var canSave: Bool = false
    var saveTitle: String? = nil
    let onDigit: (String) -> Void
    let onSeparator: () -> Void
    let onBackspace: () -> Void
    var onSave: (() -> Void)? = nil
    /// When provided, shows a chevron to collapse the keypad and reveal the form.
    var onHide: (() -> Void)? = nil

    // Phone-keypad order: 1-2-3 on top (matches iOS dialer / Cash App), then 0 row.
    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    var body: some View {
        VStack(spacing: 8) {
            if let onHide {
                HStack {
                    Spacer()
                    Button(action: onHide) {
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(String(localized: "Hide keypad"))
                }
            }
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { digit in
                        key { onDigit(digit) } label: {
                            Text(digit)
                                .font(.system(size: 26, weight: .regular, design: .rounded))
                        }
                        .accessibilityLabel(digit)
                    }
                }
            }
            HStack(spacing: 8) {
                key(action: onSeparator) {
                    Text(separator)
                        .font(.system(size: 26, weight: .regular, design: .rounded))
                }
                .disabled(!allowsDecimal)
                .opacity(allowsDecimal ? 1 : 0.25)
                .accessibilityLabel(String(localized: "Decimal point"))

                key { onDigit("0") } label: {
                    Text("0")
                        .font(.system(size: 26, weight: .regular, design: .rounded))
                }
                .accessibilityLabel("0")

                key(action: onBackspace) {
                    Image(systemName: "delete.left")
                        .font(.title3)
                }
                .accessibilityLabel(String(localized: "Delete"))
            }

            if let saveTitle, let onSave {
                Button(action: onSave) {
                    Text(saveTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func key<Label: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(NumpadKeyStyle())
    }
}

private struct NumpadKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(
                configuration.isPressed ? Color(.systemFill) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
