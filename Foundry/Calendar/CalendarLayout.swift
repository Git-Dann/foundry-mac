import Foundation

/// Pure geometry for the calendar. No SwiftUI here, so it can be tested on its own.
enum CalendarLayout {
    static let hourHeight: Double = 56
    /// A commitment has a due time but no length; it's drawn as this long.
    static let commitmentMinutes: Double = 30
    static let minimumBlockMinutes: Double = 22

    struct Span: Equatable {
        var id: String
        var start: Date
        var end: Date
    }

    struct Slot: Equatable {
        var column: Int
        var columns: Int
    }

    /// Side-by-side columns for overlapping blocks. Blocks that overlap (directly or through a
    /// chain) share a group, and each takes the first column that's free at its start.
    static func slots(_ spans: [Span]) -> [String: Slot] {
        let sorted = spans.sorted { ($0.start, $1.end) < ($1.start, $0.end) }
        var result: [String: Slot] = [:]
        var group: [(span: Span, column: Int)] = []
        var groupEnd = Date.distantPast
        var columnEnds: [Date] = []

        func closeGroup() {
            let count = max(columnEnds.count, 1)
            for item in group { result[item.span.id] = Slot(column: item.column, columns: count) }
            group = []; columnEnds = []
        }

        for span in sorted {
            if !group.isEmpty && span.start >= groupEnd { closeGroup() }
            if let free = columnEnds.firstIndex(where: { $0 <= span.start }) {
                columnEnds[free] = span.end
                group.append((span, free))
            } else {
                columnEnds.append(span.end)
                group.append((span, columnEnds.count - 1))
            }
            groupEnd = group.isEmpty ? span.end : max(groupEnd, span.end)
        }
        closeGroup()
        return result
    }

    /// Vertical position of a time within its day.
    static func y(for date: Date, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60) * hourHeight
    }

    /// Height for a block, clipped to the end of its day.
    static func height(start: Date, end: Date, calendar: Calendar = .current) -> Double {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start))!
        let minutes = max(end.timeIntervalSince(start) / 60, 0)
        let clipped = min(minutes, dayEnd.timeIntervalSince(start) / 60)
        return max(clipped, minimumBlockMinutes) / 60 * hourHeight
    }

    /// The time a drop at `y` points at, snapped to 15 minutes and kept inside the day.
    static func time(atY y: Double, on day: Date, calendar: Calendar = .current) -> Date {
        let minutes = max(0, min(24 * 60 - 15, (y / hourHeight * 60 / 15).rounded() * 15))
        return calendar.date(byAdding: .minute, value: Int(minutes), to: calendar.startOfDay(for: day))!
    }

    /// The days shown: the week containing `date` (in the calendar's own first weekday), or one day.
    static func days(around date: Date, mode: CalendarMode, calendar: Calendar = .current) -> [Date] {
        switch mode {
        case .day:
            return [calendar.startOfDay(for: date)]
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
            return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
        }
    }

    /// "Nov 2 – 8", "Oct 30 – Nov 5", or "Wednesday 4 Nov".
    static func title(for days: [Date], calendar: Calendar = .current) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        if days.count == 1 { return first.formatted(.dateTime.weekday(.wide).day().month(.wide)) }
        let sameMonth = calendar.isDate(first, equalTo: last, toGranularity: .month)
        let a = first.formatted(.dateTime.month(.abbreviated).day())
        let b = sameMonth ? last.formatted(.dateTime.day()) : last.formatted(.dateTime.month(.abbreviated).day())
        return "\(a) – \(b)"
    }

    /// "2026, Week 45".
    static func subtitle(for days: [Date], calendar: Calendar = .current) -> String {
        guard let first = days.first else { return "" }
        let year = calendar.component(.yearForWeekOfYear, from: first)
        return "\(year), Week \(calendar.component(.weekOfYear, from: first))"
    }
}

enum CalendarMode: String, CaseIterable, Identifiable {
    case week, day
    var id: String { rawValue }
    var title: String { self == .week ? "Week" : "Day" }
}
