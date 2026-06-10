import WidgetKit
import SwiftUI

/// Foundry's macOS widgets. Each renders the shared `WidgetSnapshot` written by the main app —
/// no network, no auth, no app code in the extension. System colors only (the app's asset
/// catalog isn't bundled here).
@main
struct FoundryWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AiSpendWidget()
        AgendaWidget()
        PulseHealthWidget()
    }
}

// MARK: - Timeline plumbing (shared)

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? .preview : AppGroupStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: AppGroupStore.read())
        // The app pushes reloads on every data refresh; this is just a fallback cadence.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

extension WidgetSnapshot {
    /// Believable placeholder data for the widget gallery.
    static let preview = WidgetSnapshot(
        aiSpend: .init(today: 4.20, monthToDate: 87.50, currency: "USD"),
        events: [
            .init(id: "1", title: "Client stand-up", start: Date().addingTimeInterval(3600), isAllDay: false),
            .init(id: "2", title: "Design review", start: Date().addingTimeInterval(10800), isAllDay: false),
            .init(id: "3", title: "Speakify × Gitwork", start: Date().addingTimeInterval(21600), isAllDay: false),
        ],
        scans: [
            .init(id: "1", name: "speakify.app", score: 84),
            .init(id: "2", name: "bigwedge.golf", score: 71),
            .init(id: "3", name: "fellas.co", score: 56),
        ],
        updatedAt: Date()
    )

    var hasData: Bool { updatedAt > .distantPast }
}

private func currencyText(_ amount: Double, code: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = code
    formatter.maximumFractionDigits = amount.rounded() == amount ? 0 : 2
    return formatter.string(from: amount as NSNumber) ?? "\(amount) \(code)"
}

/// Shown when the main app hasn't written a snapshot yet.
private struct OpenFoundryHint: View {
    let message: String
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "hammer.fill").foregroundStyle(.tint)
            Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
}

// MARK: - AI Spend

struct AiSpendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FoundryAiSpend", provider: SnapshotProvider()) { entry in
            AiSpendView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("AI Spend")
        .description("Today and month-to-date billed AI spend.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct AiSpendView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let spend = entry.snapshot.aiSpend {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles").font(.caption2)
                    Text("AI SPEND").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer(minLength: 0)
                Text(currencyText(spend.today, code: spend.currency))
                    .font(.system(size: family == .systemSmall ? 26 : 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                Text("Today").font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Text(currencyText(spend.monthToDate, code: spend.currency)).font(.callout.weight(.medium)).monospacedDigit()
                    Text("this month").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        } else {
            OpenFoundryHint(message: "Open Foundry to load AI spend")
        }
    }
}

// MARK: - Today's Agenda

struct AgendaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FoundryAgenda", provider: SnapshotProvider()) { entry in
            AgendaView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Agenda")
        .description("Your next Google Calendar events.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct AgendaView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var upcoming: [WidgetSnapshot.Event] {
        let cutoff = Calendar.current.date(byAdding: .hour, value: -1, to: entry.date) ?? entry.date
        return entry.snapshot.events
            .filter { $0.start >= cutoff }
            .sorted { $0.start < $1.start }
    }

    var body: some View {
        let events = Array(upcoming.prefix(family == .systemSmall ? 2 : 4))
        if events.isEmpty {
            OpenFoundryHint(message: entry.snapshot.hasData ? "Nothing coming up" : "Open Foundry's Calendar to connect")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar").font(.caption2)
                    Text("AGENDA").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                }
                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title).font(.caption.weight(.medium)).lineLimit(1)
                        Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Pulse Health

struct PulseHealthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FoundryPulseHealth", provider: SnapshotProvider()) { entry in
            PulseHealthView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Pulse Health")
        .description("Latest Pulse scan health scores.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct PulseHealthView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private func tint(_ score: Int) -> Color {
        score >= 80 ? .green : (score >= 50 ? .orange : .red)
    }

    var body: some View {
        let scans = Array(entry.snapshot.scans.prefix(family == .systemSmall ? 1 : 4))
        if scans.isEmpty {
            OpenFoundryHint(message: "Open Foundry's Pulse to load scans")
        } else if family == .systemSmall, let top = scans.first {
            VStack(spacing: 6) {
                Text("PULSE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                if let score = top.score {
                    Text("\(score)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(tint(score))
                } else {
                    Text("—").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                }
                Text(top.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.caption2)
                    Text("PULSE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                }
                ForEach(scans) { scan in
                    HStack {
                        Text(scan.name).font(.caption).lineLimit(1)
                        Spacer()
                        if let score = scan.score {
                            Text("\(score)").font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(tint(score))
                        } else {
                            Text("—").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
