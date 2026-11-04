import Foundation

/// A filter over open to-dos: a list, a tag, or a saved "smart list". Pure and Codable, so smart
/// lists can be kept in UserDefaults.
struct TodoFilter: Codable, Hashable, Identifiable, Sendable {
    enum Due: String, Codable, CaseIterable, Sendable {
        case any, overdue, today, thisWeek, noDate
        var title: String {
            switch self {
            case .any: "Any time"
            case .overdue: "Overdue"
            case .today: "Due today"
            case .thisWeek: "Due this week"
            case .noDate: "No date"
            }
        }
    }

    var id: String = UUID().uuidString
    var name: String = ""
    var symbol: String = "line.3.horizontal.decrease.circle"
    var listId: String? = nil
    var tags: [String] = []
    var minPriority: Int = 0
    var due: Due = .any
    var text: String = ""
    var includeBoard: Bool = true

    static func list(_ id: String) -> TodoFilter { TodoFilter(id: "list:" + id, listId: id) }
    static func tag(_ t: String) -> TodoFilter { TodoFilter(id: "tag:" + t, tags: [t]) }

    func matches(_ c: Commitment, now: Date, calendar: Calendar = .current) -> Bool {
        guard c.state == .open else { return false }
        if !includeBoard && c.isBoardTask { return false }
        if let listId, c.listId != listId { return false }
        if !tags.isEmpty && !tags.allSatisfy({ c.tags.contains($0) }) { return false }
        if c.priority < minPriority { return false }
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            let hay = [c.title, c.notes, c.counterpart].compactMap { $0?.lowercased() }
            if !hay.contains(where: { $0.contains(q) }) { return false }
        }
        switch due {
        case .any: return true
        case .noDate: return c.dueAt == nil
        case .overdue: return (c.dueAt.map { $0 < now }) ?? false
        case .today: return c.dueAt.map { calendar.isDate($0, inSameDayAs: now) || $0 < now } ?? false
        case .thisWeek:
            guard let d = c.dueAt, let end = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) else { return false }
            return d < end
        }
    }
}

/// The Things-style planning views. "When" (`startAt`) is when you mean to do it; `dueAt` is the
/// deadline. A to-do is in Today if either falls today or earlier.
enum Plan {
    struct Section: Identifiable, Equatable {
        var id: String
        var title: String
        var items: [Commitment]
        var isAlert = false
    }

    static func endOfToday(_ now: Date, _ cal: Calendar) -> Date {
        cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
    }

    static func isActive(_ c: Commitment, now: Date) -> Bool {
        c.state == .open && !c.isSnoozed(at: now)
    }

    static func isToday(_ c: Commitment, now: Date, calendar cal: Calendar = .current) -> Bool {
        guard isActive(c, now: now), !c.someday else { return false }
        let end = endOfToday(now, cal)
        if let s = c.startAt, s < end { return true }
        if let d = c.dueAt, d < end { return true }
        return false
    }

    /// Unsorted capture: your own to-dos with no list, no date, not someday.
    static func inbox(_ items: [Commitment], now: Date) -> [Commitment] {
        items.filter {
            isActive($0, now: now) && !$0.isBoardTask && $0.listId == nil && $0.startAt == nil && $0.dueAt == nil && !$0.someday
        }.sorted(by: manual)
    }

    /// Overdue, Today, This Evening.
    static func today(_ items: [Commitment], now: Date, calendar cal: Calendar = .current) -> [Section] {
        let todays = items.filter { isToday($0, now: now, calendar: cal) }
        let overdue = todays.filter { ($0.dueAt.map { $0 < now } ?? false) }.sorted(by: byDate)
        let rest = todays.filter { !($0.dueAt.map { $0 < now } ?? false) }
        let day = rest.filter { !$0.evening }.sorted(by: manualThenDate)
        let evening = rest.filter(\.evening).sorted(by: manualThenDate)
        return [
            Section(id: "overdue", title: "Overdue", items: overdue, isAlert: true),
            Section(id: "today", title: "Today", items: day),
            Section(id: "evening", title: "This Evening", items: evening),
        ].filter { !$0.items.isEmpty }
    }

    /// Everything planned or due after today, one section per day for a week, then by month.
    static func upcoming(_ items: [Commitment], now: Date, calendar cal: Calendar = .current) -> [Section] {
        let end = endOfToday(now, cal)
        let dated: [(Date, Commitment)] = items.compactMap { c in
            guard isActive(c, now: now), !c.someday, !isToday(c, now: now, calendar: cal) else { return nil }
            let when = [c.startAt, c.dueAt].compactMap { $0 }.filter { $0 >= end }.min()
            return when.map { ($0, c) }
        }
        let weekEnd = cal.date(byAdding: .day, value: 7, to: end)!
        var sections: [String: Section] = [:]
        var order: [String] = []
        for (when, c) in dated.sorted(by: { $0.0 < $1.0 }) {
            let key: String, title: String
            if when < weekEnd {
                let day = cal.startOfDay(for: when)
                key = "d\(Int(day.timeIntervalSince1970))"
                title = cal.isDateInTomorrow(day) ? "Tomorrow" : day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
            } else {
                let c2 = cal.dateComponents([.year, .month], from: when)
                key = "m\(c2.year ?? 0)-\(c2.month ?? 0)"
                title = when.formatted(.dateTime.month(.wide).year())
            }
            if sections[key] == nil { sections[key] = Section(id: key, title: title, items: []); order.append(key) }
            sections[key]!.items.append(c)
        }
        return order.compactMap { sections[$0] }
    }

    /// Active and not scheduled for later: what you could pick up now, grouped by list.
    static func anytime(_ items: [Commitment], lists: [TodoList], now: Date, calendar cal: Calendar = .current) -> [Section] {
        let end = endOfToday(now, cal)
        let active = items.filter { c in
            isActive(c, now: now) && !c.someday && (c.startAt.map { $0 < end } ?? true)
        }
        return grouped(active, lists: lists)
    }

    static func someday(_ items: [Commitment], lists: [TodoList], now: Date) -> [Section] {
        grouped(items.filter { isActive($0, now: now) && $0.someday }, lists: lists)
    }

    static func filtered(_ items: [Commitment], filter: TodoFilter, lists: [TodoList], now: Date) -> [Section] {
        let hits = items.filter { filter.matches($0, now: now) }
        if filter.listId != nil {
            let open = hits.filter { !$0.someday }.sorted(by: manual)
            let later = hits.filter(\.someday).sorted(by: manual)
            return [Section(id: "open", title: "", items: open), Section(id: "someday", title: "Someday", items: later)].filter { !$0.items.isEmpty }
        }
        return grouped(hits, lists: lists)
    }

    /// By list, in the lists' order; no list ("Inbox") first, board tasks by client last.
    static func grouped(_ items: [Commitment], lists: [TodoList]) -> [Section] {
        var out: [Section] = []
        let own = items.filter { !$0.isBoardTask }
        let loose = own.filter { c in c.listId == nil || !lists.contains { $0.id == c.listId } }
        if !loose.isEmpty { out.append(Section(id: "inbox", title: "Inbox", items: loose.sorted(by: manual))) }
        for l in lists {
            let these = own.filter { $0.listId == l.id }
            if !these.isEmpty { out.append(Section(id: "list:" + l.id, title: l.name, items: these.sorted(by: manual))) }
        }
        let board = Dictionary(grouping: items.filter(\.isBoardTask), by: { $0.counterpart ?? "Board" })
        for (client, these) in board.sorted(by: { $0.key < $1.key }) {
            out.append(Section(id: "board:" + client, title: "\(client) board", items: these.sorted(by: byDate)))
        }
        return out
    }

    /// Every tag in use, most used first.
    static func tags(_ items: [Commitment]) -> [(tag: String, count: Int)] {
        let counts = Dictionary(items.filter { $0.state == .open }.flatMap(\.tags).map { ($0, 1) }, uniquingKeysWith: +)
        return counts.map { ($0.key, $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }

    static func manual(_ a: Commitment, _ b: Commitment) -> Bool {
        a.orderKey != b.orderKey ? a.orderKey < b.orderKey : a.createdAt > b.createdAt
    }

    static func manualThenDate(_ a: Commitment, _ b: Commitment) -> Bool {
        if a.isBoardTask != b.isBoardTask { return !a.isBoardTask }
        return manual(a, b)
    }

    static func byDate(_ a: Commitment, _ b: Commitment) -> Bool { CommitmentGrouping.order(a, b) }
}
