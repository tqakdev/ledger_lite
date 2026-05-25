import Foundation

enum UserPreferences {
    private static let homeCurrencyKey = "homeCurrencyCode"

    static var homeCurrencyCode: String {
        get {
            UserDefaults.standard.string(forKey: homeCurrencyKey)
                ?? Constants.App.homeCurrencyDefault
        }
        set {
            UserDefaults.standard.set(newValue, forKey: homeCurrencyKey)
        }
    }
}
