import Foundation

enum UserPreferences {
    private static let homeCurrencyKey  = "homeCurrencyCode"
    private static let balanceKey       = "availableBalanceMinor"
    private static let balanceAsOfKey   = "balanceAsOfDate"
    private static let paydayKey        = "nextPayday"
    private static let incomeKey        = "paydayIncomeMinor"
    private static let safeToSpendKey   = "cachedSafeToSpendMinor"
    // Use the App Group suite so the widget extension can read the same value.
    // Falls back to UserDefaults.standard when the group container is unavailable (CI / free team).
    private static let defaults = UserDefaults(suiteName: Constants.App.appGroupIdentifier)
                                  ?? UserDefaults.standard

    static var homeCurrencyCode: String {
        get { defaults.string(forKey: homeCurrencyKey) ?? Constants.App.homeCurrencyDefault }
        set { defaults.set(newValue, forKey: homeCurrencyKey) }
    }

    // MARK: - Runway forecast inputs

    /// Current available balance in home-currency minor units. `nil` until the user sets it.
    static var availableBalanceMinor: Int? {
        get { defaults.object(forKey: balanceKey) as? Int }
        set {
            if let newValue { defaults.set(newValue, forKey: balanceKey) }
            else { defaults.removeObject(forKey: balanceKey) }
        }
    }

    /// The moment `availableBalanceMinor` was last entered. Expenses logged after this
    /// date are subtracted from the balance so the runway stays honest between updates.
    static var balanceAsOfDate: Date? {
        get { defaults.object(forKey: balanceAsOfKey) as? Date }
        set {
            if let newValue { defaults.set(newValue, forKey: balanceAsOfKey) }
            else { defaults.removeObject(forKey: balanceAsOfKey) }
        }
    }

    /// The user's next payday — the horizon the runway projects toward. `nil` until set.
    static var nextPayday: Date? {
        get { defaults.object(forKey: paydayKey) as? Date }
        set {
            if let newValue { defaults.set(newValue, forKey: paydayKey) }
            else { defaults.removeObject(forKey: paydayKey) }
        }
    }

    /// Optional income credited at payday, in home-currency minor units. Reserved for
    /// extending the runway past the next payday; `nil` when the user hasn't supplied it.
    static var paydayIncomeMinor: Int? {
        get { defaults.object(forKey: incomeKey) as? Int }
        set {
            if let newValue { defaults.set(newValue, forKey: incomeKey) }
            else { defaults.removeObject(forKey: incomeKey) }
        }
    }

    /// True once the user has supplied both a balance and a payday — the runway needs both.
    static var hasRunwaySetup: Bool {
        availableBalanceMinor != nil && nextPayday != nil
    }

    // MARK: - Widget cache

    /// Last computed "truly safe to spend / day" in home-currency minor units.
    /// Written by ForecastViewModel after every refresh so the Runway widget can display
    /// it without re-running the full projection engine.
    static var cachedSafeToSpendMinor: Int? {
        get { defaults.object(forKey: safeToSpendKey) as? Int }
        set {
            if let newValue { defaults.set(newValue, forKey: safeToSpendKey) }
            else { defaults.removeObject(forKey: safeToSpendKey) }
        }
    }
}
