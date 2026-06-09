import SwiftUI

/// The app's single source of visual identity. Centralising colour, radius, and surface
/// styling is what turns a default-SwiftUI look into a recognisable product — and keeps
/// every screen speaking the same language instead of scattering ad-hoc `.mint`/`.orange`.
///
/// Brand hue is a confident teal (see Assets `AccentColor`); the "truly safe to spend"
/// figure in brand teal is the signature. Amber = bills/caution, red = danger.
enum Theme {
    /// Brand chrome: tab selection, buttons, links, the runway line, FAB.
    static let brand = Color.accentColor
    /// Positive / "safe to spend" — the hero state shares the brand hue on purpose.
    static let positive = Color.accentColor
    /// Upcoming bills, above-average spend.
    static let caution = Color("Caution")
    /// Over budget, projected to run out, destructive actions.
    static let danger = Color("Danger")

    // Geometry — continuous ("squircle") corners read more designed than the default.
    static let cardRadius: CGFloat = 22
    static let cardCorner: RoundedRectangle = RoundedRectangle(cornerRadius: 22, style: .continuous)

    /// Subtle brand wash used on hero surfaces.
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brand.opacity(0.18), Color(.secondarySystemGroupedBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Rounded display font for monetary figures and headline numbers.
    static func figure(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

// MARK: - Signature surfaces

/// The app's card surface: continuous corners, a hairline border, and a soft shadow.
/// Replaces the bare `Color(.secondarySystemGroupedBackground)` rounded rectangles that
/// every template ships, giving consistent depth across screens.
private struct CardModifier: ViewModifier {
    var tinted: Bool
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                if tinted {
                    Theme.cardCorner.fill(Theme.brandGradient)
                } else {
                    Theme.cardCorner.fill(Color(.secondarySystemGroupedBackground))
                }
            }
            .overlay {
                Theme.cardCorner.strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
}

/// Compact status chip (velocity, streak, etc.) — one consistent shape app-wide.
private struct ChipModifier: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

extension View {
    /// Wraps the view in the signature card surface.
    func card(tinted: Bool = false, padding: CGFloat = 16) -> some View {
        modifier(CardModifier(tinted: tinted, padding: padding))
    }

    /// Styles content as a compact coloured status chip.
    func chip(_ color: Color) -> some View {
        modifier(ChipModifier(color: color))
    }
}
