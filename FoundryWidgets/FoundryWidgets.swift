import SwiftUI
import WidgetKit

/// Today's commitments, read from the snapshot the app writes. No network or sign-in here.
struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: WidgetSnapshot(
            signedIn: true,
            items: [
                .init(id: "1", title: "Send the kick-off notes", dueAt: Date().addingTimeInterval(3600), counterpart: nil),
                .init(id: "2", title: "Share the revised quote", dueAt: Date().addingTimeInterval(7200), counterpart: nil),
            ],
            reviewCount: 1
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : TodayEntry(date: Date(), snapshot: AppGroupStore.read()))
    }

    /// One entry now, then one at each due time (so a row turns overdue on time) and at midnight.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let snapshot = AppGroupStore.read()
        let now = Date()
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        let changes = snapshot.items.compactMap(\.dueAt).filter { $0 > now && $0 < midnight }
        let dates = ([now] + changes + [midnight]).sorted()
        completion(Timeline(entries: dates.map { TodayEntry(date: $0, snapshot: snapshot) }, policy: .after(midnight)))
    }
}

struct TodayWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        TodayWidgetView(snapshot: entry.snapshot, date: entry.date, family: family)
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(URL(string: "foundry://commitment/"))
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "co.gitwork.foundry.today", provider: TodayProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("What you've promised for today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct FoundryWidgetBundle: WidgetBundle {
    var body: some Widget { TodayWidget() }
}
