import AppIntents

struct LedgerLiteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Log an expense in \(.applicationName)",
                "Add expense in \(.applicationName)",
            ],
            shortTitle: "Log Expense",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: TodayTotalIntent(),
            phrases: [
                "What did I spend today in \(.applicationName)",
                "Today's total in \(.applicationName)",
            ],
            shortTitle: "Today's Total",
            systemImageName: "dollarsign.circle"
        )
    }
}
