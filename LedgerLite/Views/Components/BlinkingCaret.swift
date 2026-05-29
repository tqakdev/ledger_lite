import SwiftUI

/// A blinking text caret for the amount displays.
///
/// Owns its own `visible` state so the repeating blink animation only re-renders
/// this view — not the parent sheet. (Hoisting the blink state into the sheet
/// caused the whole body, including the navigation toolbar, to re-evaluate twice
/// a second, which made the Cancel/Save buttons flicker and the amount text jitter.)
struct BlinkingCaret: View {
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.accentColor)
            .frame(width: 3, height: height)
            .opacity(reduceMotion ? 1 : (visible ? 1 : 0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}
