import Foundation

/// The board tasks assigned to you, from `GET /api/tasks?assigneeId=<you>` (docs-by-gitwork).
/// Shown in the same lists as your own to-dos, as `Commitment`s with source `.board`, so Today
/// is one place to look. Ticking one marks it done on the board.
struct BoardTaskDTO: Decodable, Sendable {
    struct Client: Decodable, Sendable { var id: String; var name: String; var slug: String }
    struct Person: Decodable, Sendable { var id: String }
    var id: String
    var assignees: [Person]?
    var title: String
    var status: String
    var dueDate: String?
    var completedAt: Date?
    var archivedAt: Date?
    var parentId: String?
    var client: Client?
    var createdAt: Date
    var updatedAt: Date
}

enum BoardTasks {
    /// A board task's due date is a day, not a time. It is shown at 17:00 local on that day, the
    /// same time a typed "fri" means.
    static let dueHour = 17

    /// "2026-11-06" or "2026-11-06T00:00:00.000Z" → 17:00 local on 6 Nov. Only the date is read:
    /// a midnight-UTC timestamp must not slip to the day before west of Greenwich.
    static func dueAt(_ raw: String?, calendar: Calendar = .current) -> Date? {
        guard let raw, raw.count >= 10 else { return nil }
        let parts = raw.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: dueHour))
    }

    /// The day a due time falls on, as the board wants it ("2026-11-06").
    static func dueDate(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Which assigned tasks are to-dos: anything in progress or planned for a day (a backlog task
    /// with no date is someone's idea for later, not today's work), plus ones finished in the
    /// last two weeks so Done shows them. Subtasks show only through their parent.
    /// ⚠️ `assigneeId` is also checked here: the endpoint returns the whole workspace's board
    /// when the filter is missing, and someone else's task must never appear as yours.
    static func isRelevant(_ t: BoardTaskDTO, for userId: String, now: Date) -> Bool {
        guard !userId.isEmpty, t.assignees?.contains(where: { $0.id == userId }) == true else { return false }
        if t.archivedAt != nil || t.parentId != nil { return false }
        switch t.status {
        case "DONE":
            guard let done = t.completedAt else { return false }
            return now.timeIntervalSince(done) < 14 * 86_400
        case "BACKLOG":
            return t.dueDate != nil
        default:
            return true
        }
    }

    static func commitment(_ t: BoardTaskDTO, webPath: (BoardTaskDTO) -> String?) -> Commitment {
        let done = t.status == "DONE"
        return Commitment(
            id: Commitment.boardPrefix + t.id,
            title: t.title,
            notes: nil,
            dueAt: dueAt(t.dueDate),
            state: done ? .done : .open,
            source: .board,
            counterpart: t.client?.name,
            quote: nil,
            evidenceLabel: t.client.map { "\($0.name) board" },
            evidenceUrl: webPath(t),
            evidenceAt: nil,
            reason: nil,
            snoozedUntil: nil,
            doneAt: done ? (t.completedAt ?? t.updatedAt) : nil,
            createdAt: t.createdAt,
            updatedAt: t.updatedAt,
            boardStatus: t.status
        )
    }

    static func path(_ t: BoardTaskDTO) -> String? {
        guard let slug = t.client?.slug else { return nil }
        return "/app/portal/\(slug)/tasks?task=\(t.id)"
    }

    /// The board status a to-do edit asks for: ticked → DONE; reopened → back to where it was
    /// (or To do, if it was already done when it reached the app).
    static func status(for state: Commitment.State, previous: String?) -> String? {
        switch state {
        case .done: return "DONE"
        case .open:
            guard let previous, previous != "DONE" else { return "TODO" }
            return previous
        case .suggested, .dismissed: return nil
        }
    }
}
