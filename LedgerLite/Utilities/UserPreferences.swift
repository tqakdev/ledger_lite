import Foundation

enum UserPreferences {
    private static let homeCurrencyKey = "homeCurrencyCode"
    // Use the App Group suite so the widget extension can read the same value.
    // Falls back to UserDefaults.standard when the group container is unavailable (CI / free team).
    private static let defaults = UserDefaults(suiteName: Constants.App.appGroupIdentifier)
                                  ?? UserDefaults.standard

    static var homeCurrencyCode: String {
        get { defaults.string(forKey: homeCurrencyKey) ?? Constants.App.homeCurrencyDefault }
        set { defaults.set(newValue, forKey: homeCurrencyKey) }
    }
}
