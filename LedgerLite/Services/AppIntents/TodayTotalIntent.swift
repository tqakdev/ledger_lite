import AppIntents

/// "What did I spend today?" — read-only Siri query.
struct TodayTotalIntent: AppIntent {
    static var title: LocalizedStringResource = "Today's Spending Total"
    static var description = IntentDescription("Get today's total spending from LedgerLite.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let service = WidgetDataService() else {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "Could not read Ledger Lite data.")))
        }
        let summary = service.todaySummary()
        let total   = Money(minorUnits: summary.totalMinor, currencyCode: summary.currencyCode).formatted()
        let count   = summary.expenses.count
        let dialog: IntentDialog = count == 0
            ? IntentDialog(stringLiteral: String(localized: "You haven't logged any expenses today."))
            : IntentDialog(stringLiteral: count == 1
                ? String(localized: "You've spent \(total) across 1 expense today.")
                : String(localized: "You've spent \(total) across \(count) expenses today."))
        return .result(dialog: dialog)
    }
}
