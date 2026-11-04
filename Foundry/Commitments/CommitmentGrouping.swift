import Foundation

/// Where an open commitment sits in the list. Pure: everything is decided from `now` + calendar.
enum DueGroup: String, CaseIterable, Identifiable, Sendable {
    case overdue, today, next7, later, noDate, snoozed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .next7: "Next 7 days"
        case .later: "Later"
        case .noDate: "No date"
        case .snoozed: "Snoozed"
        }
    }
}

enum CommitmentGrouping {
    /// Overdue means the due time has passed. Today means due later today. A snoozed commitment
    /// sits apart until its snooze ends, whatever its date.
    static func group(_ c: Commitment, now: Date, calendar: Calendar = .current) -> DueGroup {
        if c.isSnoozed(at: now) { return .snoozed }
        guard let due = c.dueAt else { return .noDate }
        if due < now { return .overdue }
        if calendar.isDate(due, inSameDayAs: now) { return .today }
        let startOfToday = calendar.startOfDay(for: now)
        if let limit = calendar.date(byAdding: .day, value: 8, to: startOfToday), due < limit { return .next7 }
        return .later
    }

    /// Open commitments grouped and sorted (soonest first, undated by newest). Empty groups dropped.
    static func sections(
        _ items: [Commitment], now: Date, calendar: Calendar = .current, include: Set<DueGroup> = Set(DueGroup.allCases)
    ) -> [(group: DueGroup, items: [Commitment])] {
        let open = items.filter { $0.state == .open }
        let buckets = Dictionary(grouping: open) { group($0, now: now, calendar: calendar) }
        return DueGroup.allCases.compactMap { g in
            guard include.contains(g), let list = buckets[g], !list.isEmpty else { return nil }
            return (g, list.sorted(by: order))
        }
    }

    static func order(_ a: Commitment, _ b: Commitment) -> Bool {
        switch (a.dueAt, b.dueAt) {
        case let (x?, y?) where x != y: return x < y
        case (nil, _?): return false
        case (_?, nil): return true
        default: return a.createdAt > b.createdAt
        }
    }

    static func suggestions(_ items: [Commitment]) -> [Commitment] {
        items.filter { $0.state == .suggested }.sorted { ($0.evidenceAt ?? $0.createdAt) > ($1.evidenceAt ?? $1.createdAt) }
    }

    static func done(_ items: [Commitment]) -> [Commitment] {
        items.filter { $0.state == .done }.sorted { ($0.doneAt ?? $0.updatedAt) > ($1.doneAt ?? $1.updatedAt) }
    }

    /// What the menu bar's title and the widget count: due today or already late.
    static func dueNowCount(_ items: [Commitment], now: Date, calendar: Calendar = .current) -> Int {
        items.filter { $0.state == .open }.filter {
            let g = group($0, now: now, calendar: calendar)
            return g == .overdue || g == .today
        }.count
    }
}

/// The three snooze choices, and when each one ends.
enum SnoozeOption: String, CaseIterable, Identifiable, Sendable {
    case laterToday, tomorrow, nextMonday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .laterToday: "Later today"
        case .tomorrow: "Tomorrow, 09:00"
        case .nextMonday: "Next Monday, 09:00"
        }
    }

    /// Later today is three hours on, but never past 21:00; late in the evening it rolls to
    /// tomorrow morning instead of snoozing into the night.
    func until(from now: Date, calendar: Calendar = .current) -> Date {
        let nineAM = { (day: Date) in calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)! }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        switch self {
        case .laterToday:
            let later = now.addingTimeInterval(3 * 3600)
            let cutoff = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: now)!
            return later <= cutoff ? later : nineAM(tomorrow)
        case .tomorrow:
            return nineAM(tomorrow)
        case .nextMonday:
            let monday = calendar.nextDate(
                after: now, matching: DateComponents(hour: 9, minute: 0, weekday: 2), matchingPolicy: .nextTime
            )!
            // "Next Monday" from a Sunday evening is tomorrow; from Monday morning it's a week on.
            return monday
        }
    }
}
