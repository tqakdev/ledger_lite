import WidgetKit
import SwiftUI

// Phase 8: full widget implementation (today's total, last 3 expenses, deep links).
// Reads SwiftData via the shared App Group store URL — same container as the main app.

struct LedgerLiteEntry: TimelineEntry {
    let date: Date
}

struct LedgerLiteWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LedgerLiteEntry {
        LedgerLiteEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (LedgerLiteEntry) -> Void) {
        completion(LedgerLiteEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LedgerLiteEntry>) -> Void) {
        completion(Timeline(entries: [LedgerLiteEntry(date: .now)], policy: .never))
    }
}

struct LedgerLiteWidgetEntryView: View {
    let entry: LedgerLiteEntry

    var body: some View {
        Text(String(localized: "LedgerLite — Phase 8"))
            .font(.caption)
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct LedgerLiteWidget: Widget {
    let kind = "LedgerLiteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LedgerLiteWidgetProvider()) { entry in
            LedgerLiteWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(String(localized: "LedgerLite"))
        .description(String(localized: "See today's spending at a glance."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
