import OSLog

/// App-wide loggers, one per architectural layer. Use these everywhere — never `print()`.
enum AppLogger {
    static let currency      = Logger(subsystem: "com.enes.ledgerlite", category: "currency")
    static let data          = Logger(subsystem: "com.enes.ledgerlite", category: "data")
    static let subscriptions = Logger(subsystem: "com.enes.ledgerlite", category: "subscriptions")
    static let ui            = Logger(subsystem: "com.enes.ledgerlite", category: "ui")
}
