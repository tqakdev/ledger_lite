import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("homeCurrencyCode", store: UserDefaults(suiteName: Constants.App.appGroupIdentifier))
    private var homeCurrencyCode = Constants.App.homeCurrencyDefault
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            welcomePage.tag(0)
            currencyPage.tag(1)
            readyPage.tag(2)
            notificationsPage.tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .ignoresSafeArea()
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 72)
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.accentColor)
            Spacer().frame(height: 32)
            VStack(spacing: 12) {
                Text(String(localized: "Welcome to LedgerLite"))
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(String(localized: "Track daily spending, manage subscriptions, and understand where your money goes."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            nextButton(String(localized: "Get Started")) { withAnimation { page = 1 } }
            Spacer().frame(height: 56)
        }
    }

    private var currencyPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 72)
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.accentColor)
            Spacer().frame(height: 24)
            VStack(spacing: 12) {
                Text(String(localized: "Pick Your Currency"))
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(String(localized: "Choose the currency you spend in most. You can change this any time in Settings."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer().frame(height: 24)
            Picker(String(localized: "Currency"), selection: $homeCurrencyCode) {
                ForEach(Constants.App.supportedCurrencies, id: \.self) { code in
                    Text(code).tag(code)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)
            Spacer()
            nextButton(String(localized: "Continue")) { withAnimation { page = 2 } }
            Spacer().frame(height: 56)
        }
    }

    private var readyPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 72)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            Spacer().frame(height: 32)
            VStack(spacing: 12) {
                Text(String(localized: "You're All Set"))
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(String(localized: "Tap the + button on the Today tab to log your first expense. Swipe left on any row to delete it."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            nextButton(String(localized: "Next")) { withAnimation { page = 3 } }
            Spacer().frame(height: 56)
        }
    }

    private var notificationsPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 72)
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.accentColor)
            Spacer().frame(height: 32)
            VStack(spacing: 12) {
                Text(String(localized: "Stay on Top of Bills"))
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(String(localized: "Get notified 2 days before each subscription billing date so you're never surprised."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            nextButton(String(localized: "Allow Notifications")) {
                Task {
                    _ = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .badge, .sound])
                    hasCompletedOnboarding = true
                }
            }
            Button(String(localized: "Skip")) {
                hasCompletedOnboarding = true
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Spacer().frame(height: 56)
        }
    }

    // MARK: - Shared button

    private func nextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 32)
    }
}

#if DEBUG
#Preview {
    OnboardingView()
}
#endif
