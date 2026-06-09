import SwiftUI

/// The app's single source of visual identity. Centralising colour, radius, surface,
/// and motion tokens is what turns a default-SwiftUI look into a recognisable product —
/// and keeps every screen speaking the same language instead of scattering ad-hoc
/// `.mint`/`.orange`.
///
/// The design language ("night runway"): one signature dark **ink** surface carries the
/// forecast — a deep teal-black card with a glowing mint line, like runway lights at
/// night. Everything else stays light, native, and quiet so the hero owns the screen.
/// Brand teal is the chrome; amber = bills/caution; red = danger.
enum Theme {

    // MARK: Colour

    /// Brand chrome: tab selection, buttons, links, the runway line, FAB.
    static let brand = Color.accentColor
    /// Deep partner to `brand`, used as the dark stop of accent gradients.
    static let brandDeep = Color("AccentDeep")
    /// Positive / "safe to spend" — shares the brand hue on purpose.
    static let positive = Color.accentColor
    /// Upcoming bills, above-average spend.
    static let caution = Color("Caution")
    /// Over budget, projected to run out, destructive actions.
    static let danger = Color("Danger")

    /// Hero surface — dark teal-black in BOTH colour schemes, like a payment card.
    static let ink = Color("Ink")
    /// Lighter ink for the hero gradient's top-leading corner.
    static let inkSoft = Color("InkSoft")
    /// Mint glow: the signature figure/line colour on ink.
    static let glow = Color("Glow")

    /// Content colours for ink surfaces. The ink card is dark in both colour schemes,
    /// so these are fixed rather than adaptive — never use `.primary`/`.secondary` on ink.
    enum OnInk {
        static let primary   = Color.white
        static let secondary = Color.white.opacity(0.64)
        static let tertiary  = Color.white.opacity(0.42)
        /// Hairline strokes and separators on ink.
        static let hairline  = Color.white.opacity(0.10)
        /// Recessed fills (chips, fields, bar tracks) on ink.
        static let fill      = Color.white.opacity(0.12)
        static let positive  = Theme.glow
        static let caution   = Color(hex: "#FFC56B")
        static let danger    = Color(hex: "#FF8A80")
    }

    // MARK: Geometry

    /// Continuous ("squircle") corners read more designed than the default.
    static let cardRadius: CGFloat = 22
    static let cardCorner = RoundedRectangle(cornerRadius: 22, style: .continuous)
    static let heroCorner = RoundedRectangle(cornerRadius: 26, style: .continuous)

    // MARK: Gradients

    /// Subtle brand wash used on light tinted surfaces.
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brand.opacity(0.18), Color(.secondarySystemGroupedBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The hero ink surface.
    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [inkSoft, ink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Accent gradient for prominent buttons and the FAB.
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [brand, brandDeep],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: Type

    /// Rounded display font for monetary figures and headline numbers.
    static func figure(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }

    /// Rounded headline used for card/section titles — a quiet, consistent signature.
    static var cardTitle: Font {
        .system(.headline, design: .rounded, weight: .semibold)
    }

    // MARK: Motion

    /// Default interactive spring — snappy without wobble.
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
    /// Softer spring for content that slides or grows into place.
    static let springSoft = Animation.spring(response: 0.45, dampingFraction: 0.85)
}

// MARK: - Signature surfaces

/// The app's light card surface: continuous corners, a hairline border, and a soft
/// shadow. Replaces the bare `Color(.secondarySystemGroupedBackground)` rounded
/// rectangles that every template ships, giving consistent depth across screens.
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

/// The hero ink surface: deep teal-black gradient, a faint top light-edge (as if lit
/// from above), and a coloured ambient shadow. Reserved for the few moments that ARE
/// the brand — the runway forecast, the lock screen, the widget.
private struct HeroCardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background { Theme.heroCorner.fill(Theme.heroGradient) }
            .overlay {
                Theme.heroCorner.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: Theme.ink.opacity(0.30), radius: 14, x: 0, y: 8)
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
    /// Wraps the view in the signature light card surface.
    func card(tinted: Bool = false, padding: CGFloat = 16) -> some View {
        modifier(CardModifier(tinted: tinted, padding: padding))
    }

    /// Wraps the view in the hero ink surface.
    func heroCard(padding: CGFloat = 20) -> some View {
        modifier(HeroCardModifier(padding: padding))
    }

    /// Styles content as a compact coloured status chip.
    func chip(_ color: Color) -> some View {
        modifier(ChipModifier(color: color))
    }
}

// MARK: - Icon tile

/// Rounded-square tinted icon used in rows, feature lists, and section headers.
/// One consistent treatment instead of ad-hoc circles and squares per screen.
struct IconTile: View {
    let systemName: String
    var color: Color = Theme.brand
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(color.opacity(0.14))
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Brand button

/// The app's prominent button: accent-gradient capsule with a pressed spring.
/// Replaces stock `.borderedProminent` at the moments that matter (onboarding,
/// save bars, empty-state CTAs) so even buttons carry the brand.
struct BrandButtonStyle: ButtonStyle {
    var fullWidth: Bool = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .padding(.horizontal, 24)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(Theme.accentGradient, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1.0) : 0.45)
            .saturation(isEnabled ? 1.0 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .shadow(
                color: Theme.brand.opacity(isEnabled ? (configuration.isPressed ? 0.18 : 0.32) : 0),
                radius: 12, x: 0, y: 6
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
