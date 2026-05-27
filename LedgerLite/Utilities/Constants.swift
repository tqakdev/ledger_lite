import Foundation

enum Constants {
    enum App {
        static let appGroupIdentifier   = "group.com.enes.ledgerlite"
        static let homeCurrencyDefault  = "USD"

        /// ~30 major currencies verified against Frankfurter's /currencies endpoint at build time.
        /// BGN and RON added for EU users; IDR included despite 0-decimal practice (ISO says 2).
        static let supportedCurrencies: [String] = [
            "USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "CNY",
            "HKD", "SGD", "NZD", "SEK", "NOK", "DKK", "MXN", "BRL",
            "INR", "KRW", "TRY", "ZAR", "SAR", "AED", "THB", "MYR",
            "IDR", "PLN", "CZK", "HUF", "ILS", "PHP", "BGN", "RON",
        ]
    }

    enum URLs {
        static let frankfurterBase      = URL(string: "https://api.frankfurter.dev/v1")!
        static let openERAPIBase        = URL(string: "https://open.er-api.com")!
    }
}
