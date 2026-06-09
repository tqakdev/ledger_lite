import WidgetKit
import SwiftUI

@main
struct LedgerLiteWidgetBundle: WidgetBundle {
    var body: some Widget {
        LedgerLiteRunwayWidget()
        LedgerLiteTodayWidget()
        LedgerLiteSubscriptionsWidget()
    }
}
