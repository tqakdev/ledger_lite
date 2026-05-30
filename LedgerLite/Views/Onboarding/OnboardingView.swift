import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("homeCurrencyCode", store: UserDefaults(suiteName: Constants.App.appGroupIdentifier))
    private var homeCurrencyCode = Constants.App.homeCurrencyDefault

    @State private var page = 0
    @State private var direction: Int = 1

    private let totalPages = 3

    var body: some View {
        ZStack(alignment: .bottom) {
            pageContent
                .id(page)
                .transition(.asymmetric(
                    insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                    removal:   .move(edge: direction > 0 ? .leading  : .trailing).combined(with: .opacity)
                ))

            progressDots
                .padding(.bottom, 16)
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: page)
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if value.translation.width < 0, page < totalPages - 1 {
                        advance(by: 1)
                    } else if value.translation.width > 0, page > 0 {
                        advance(by: -1)
                    }
                }
        )
        .ignoresSafeArea()
    }

    // MARK: - Page routing

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case 0: welcomePage
        case 1: currencyPage
        default: notificationsPage
        }
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 80)

                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 120, height: 120)
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 58))
                        .foregroundStyle(Color.accentColor)
                }

                Spacer().frame(height: 28)

                VStack(spacing: 10) {
                    Text(String(localized: "Welcome to Ledger Lite"))
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text(String(localized: "Track daily spending, manage subscriptions, and understand where your money goes."))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer().frame(height: 36)

                VStack(spacing: 12) {
                    featureRow(
                        icon: "plus.circle.fill",
                        color: Color.accentColor,
                        title: String(localized: "Quick Add"),
                        subtitle: String(localized: "Log any expense in seconds, with smart merchant suggestions.")
                    )
                    featureRow(
                        icon: "repeat.circle.fill",
                        color: .purple,
                        title: String(localized: "Subscriptions"),
                        subtitle: String(localized: "Track recurring bills and get notified before they charge.")
                    )
                    featureRow(
                        icon: "chart.pie.fill",
                        color: .orange,
                        title: String(localized: "Insights"),
                        subtitle: String(localized: "See spending trends and category breakdowns at a glance.")
                    )
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 48)

                nextButton(String(localized: "Get Started")) { advance(by: 1) }

                Spacer().frame(height: 80)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Currency

    private var currencyPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 72)

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(Color.accentColor)
            }

            Spacer().frame(height: 24)

            VStack(spacing: 10) {
                Text(String(localized: "Pick Your Currency"))
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(String(localized: "Choose the currency you spend in most. You can change this any time in Settings."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer().frame(height: 20)

            Picker(String(localized: "Currency"), selection: $homeCurrencyCode) {
                ForEach(Constants.App.supportedCurrencies, id: \.self) { code in
                    Text(code).tag(code)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)

            Spacer()

            nextButton(String(localized: "Continue")) { advance(by: 1) }
            Spacer().frame(height: 80)
        }
    }

    // MARK: - Notifications

    private var notificationsPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 80)

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(Color.accentColor)
            }

            Spacer().frame(height: 28)

            VStack(spacing: 10) {
                Text(String(localized: "Stay on Top of Bills"))
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(String(localized: "Get notified 2 days before each subscription billing date so you're never surprised."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer().frame(height: 32)

            VStack(spacing: 12) {
                notifBenefitRow(icon: "clock.badge.checkmark.fill", text: String(localized: "2-day advance billing reminders"))
                notifBenefitRow(icon: "exclamationmark.triangle.fill",  text: String(localized: "Budget limit warnings"))
                notifBenefitRow(icon: "bell.slash.fill", text: String(localized: "No spam — only what matters"))
            }
            .padding(.horizontal, 40)

            Spacer()

            nextButton(String(localized: "Allow Notifications")) {
                Task {
                    _ = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .badge, .sound])
                    hasCompletedOnboarding = true
                }
            }

            Button(String(localized: "Skip for Now")) {
                hasCompletedOnboarding = true
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 12)

            Spacer().frame(height: 80)
        }
    }

    // MARK: - Components

    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func notifBenefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

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

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Color.accentColor : Color.accentColor.opacity(0.25))
                    .frame(width: i == page ? 20 : 8, height: 8)
                    .animation(.spring(duration: 0.3), value: page)
            }
        }
    }

    // MARK: - Navigation

    private func advance(by delta: Int) {
        direction = delta
        withAnimation {
            page = max(0, min(page + delta, totalPages - 1))
        }
    }
}



#if DEBUG
#Preview {
    OnboardingView()
}
#endif
