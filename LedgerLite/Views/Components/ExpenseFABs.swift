import SwiftUI

/// Floating "+" quick-add button. Shared by the Runway and Spending screens so the
/// capture affordance is identical everywhere expenses can be logged.
struct AddExpenseFAB: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isVisible: Bool
    var isSheetOpen: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: Color.accentColor.opacity(0.35), radius: 10, x: 0, y: 5)
                .rotationEffect(reduceMotion ? .zero : .degrees(isSheetOpen ? 45 : 0))
                .animation(.spring(response: 0.3), value: isSheetOpen)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .accessibilityLabel(String(localized: "Add expense"))
        .scaleEffect(reduceMotion ? 1.0 : (isVisible ? 1.0 : 0.01))
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.4), value: isVisible)
        .onAppear { isVisible = true }
    }
}

/// Secondary "scan receipt" button, shown above the add FAB.
struct ScanReceiptFAB: View {
    @Binding var isVisible: Bool
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: "doc.text.viewfinder")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.accentColor.opacity(0.25), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
        }
        .padding(.trailing, 26)
        .accessibilityLabel(String(localized: "Scan receipt"))
        .scaleEffect(isVisible ? 1.0 : 0.01)
        .animation(.spring(duration: 0.4, bounce: 0.4), value: isVisible)
    }
}

/// The stacked scan + add FAB cluster used in the bottom-trailing corner.
struct ExpenseFABCluster: View {
    @Binding var isVisible: Bool
    var isSheetOpen: Bool = false
    let onAdd: () -> Void
    let onScan: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 14) {
            ScanReceiptFAB(isVisible: $isVisible, action: onScan)
            AddExpenseFAB(isVisible: $isVisible, isSheetOpen: isSheetOpen, action: onAdd)
        }
    }
}
