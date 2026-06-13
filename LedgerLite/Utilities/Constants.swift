import Foundation

enum Constants {
    enum App {
        static let appGroupIdentifier   = "group.com.enes.ledgerlite"
        static let homeCurrencyDefault  = "USD"

        /// ~30 major currencies verified against Frankfurter's /currencies endpoint at build time.
        /// BGN and RON added for EU users; IDR included despite 0-decimal practice (ISO says 2).
        static let supportedCurrencies: [String] = [
            "USD", "EUR", "GBP", "KZT", "JPY", "CHF", "CAD", "AUD",
            "CNY", "HKD", "SGD", "NZD", "SEK", "NOK", "DKK", "MXN",
            "BRL", "INR", "KRW", "TRY", "ZAR", "SAR", "AED", "THB",
            "MYR", "IDR", "PLN", "CZK", "HUF", "ILS", "PHP", "BGN",
            "RON",
        ]

        /// Single source of truth for currency-symbol prefixes shared by
        /// `SubscriptionDetector` and `ReceiptTextParser`. Most-specific prefix
        /// first so "$" (USD) doesn't shadow "A$" (AUD) or "R$" (BRL).
        /// "RM" (Malaysian Ringgit) is alphabetic and deliberately NOT here — both
        /// parsers match it with a `\bRM\s?\d` word boundary so it can't fire
        /// inside words like "FARM 9.99" or "SUPERMARKET".
        static let currencySymbolMap: [(symbol: String, code: String)] = [
            ("HK$", "HKD"), ("NZ$", "NZD"), ("A$", "AUD"), ("C$", "CAD"), ("S$", "SGD"),
            ("R$", "BRL"), ("₹", "INR"), ("€", "EUR"), ("£", "GBP"), ("¥", "JPY"),
            ("₩", "KRW"), ("₺", "TRY"), ("฿", "THB"), ("$", "USD"),
        ]
    }

    enum URLs {
        static let frankfurterBase      = URL(string: "https://api.frankfurter.dev/v1")!
        static let openERAPIBase        = URL(string: "https://open.er-api.com")!
    }
}
