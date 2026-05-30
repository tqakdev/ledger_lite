import SwiftUI
import LocalAuthentication

struct LockScreenView: View {
    let onUnlock: () -> Void

    @State private var failed = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                VStack(spacing: 8) {
                    Text(String(localized: "Ledger Lite is Locked"))
                        .font(.title2.bold())
                    if failed {
                        Text(String(localized: "Authentication failed. Try again."))
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                Button { authenticate() } label: {
                    Label(String(localized: "Unlock"), systemImage: "lock.open.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
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
