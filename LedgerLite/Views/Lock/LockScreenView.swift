import SwiftUI
import LocalAuthentication

/// Opaque brand surface shown while the scene is inactive (app switcher, system
/// sheets) so the snapshot iOS captures never contains financial data.
struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Theme.heroGradient.ignoresSafeArea()
            ZStack {
                Circle()
                    .fill(Theme.glow.opacity(0.12))
                    .frame(width: 132, height: 132)
                Image(systemName: "lock.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(Theme.glow)
            }
        }
    }
}

/// Privacy is the product's identity, so the lock screen is a full-bleed brand
/// moment: the ink surface with a glow lock, mirroring the runway hero.
struct LockScreenView: View {
    let onUnlock: () -> Void

    @State private var failed = false

    var body: some View {
        ZStack {
            Theme.heroGradient.ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Theme.glow.opacity(0.12))
                        .frame(width: 132, height: 132)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 56, weight: .medium))
                        .foregroundStyle(Theme.glow)
                }
                VStack(spacing: 8) {
                    Text(String(localized: "Ledger Lite is Locked"))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.OnInk.primary)
                    if failed {
                        Text(String(localized: "Authentication failed. Try again."))
                            .font(.subheadline)
                            .foregroundStyle(Theme.OnInk.danger)
                    }
                }
                Spacer()
                Button { authenticate() } label: {
                    Label(String(localized: "Unlock"), systemImage: "lock.open.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.glow, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                Spacer().frame(height: 48)
            }
        }
        .onAppear { authenticate() }
    }

    private func authenticate() {
        let ctx = LAContext()
        ctx.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: String(localized: "Unlock Ledger Lite")
        ) { success, _ in
            DispatchQueue.main.async {
                if success { onUnlock() } else { failed = true }
            }
        }
    }
}
