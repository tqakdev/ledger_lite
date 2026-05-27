import UserNotifications

final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationDelegate()
    private override init() {}

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.identifier
        let path: String?
        if id.hasPrefix("budget-") {
            path = "insights"
        } else if id.hasPrefix("sub-") {
            path = "subscriptions"
        } else {
            path = nil
        }
        if let path, let url = URL(string: "ledgerlite://\(path)") {
            NotificationCenter.default.post(
                name: Notification.Name("LedgerLiteDeepLink"),
                object: url
            )
        }
        completionHandler()
    }
}
