import Foundation

/// One line of a to-do's checklist.
struct ChecklistItem: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var text: String
    var done: Bool

    init(id: String = UUID().uuidString, text: String, done: Bool = false) {
        self.id = id; self.text = text; self.done = done
    }
}

/// A list (project) of to-dos. Mirrors `CommitmentListDTO`.
struct TodoList: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var color: String?
    var symbol: String?
    var area: String?
    var orderKey: Double
    var archived: Bool

    static let colors = ["red", "orange", "yellow", "green", "mint", "teal", "cyan", "blue", "indigo", "purple", "pink", "brown", "gray"]
    static let symbols = ["list.bullet", "folder", "briefcase", "person.2", "house", "cart", "book", "star", "flag",
                          "hammer", "paintbrush", "chart.bar", "airplane", "heart", "leaf", "bolt", "graduationcap", "building.2"]
}

extension Commitment {
    /// The decoder tolerates a server that doesn't yet send the planning fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        state = try c.decode(State.self, forKey: .state)
        source = try c.decode(Source.self, forKey: .source)
        counterpart = try c.decodeIfPresent(String.self, forKey: .counterpart)
        quote = try c.decodeIfPresent(String.self, forKey: .quote)
        evidenceLabel = try c.decodeIfPresent(String.self, forKey: .evidenceLabel)
        evidenceUrl = try c.decodeIfPresent(String.self, forKey: .evidenceUrl)
        evidenceAt = try c.decodeIfPresent(Date.self, forKey: .evidenceAt)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        boardStatus = try c.decodeIfPresent(String.self, forKey: .boardStatus)
        listId = try c.decodeIfPresent(String.self, forKey: .listId)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        startAt = try c.decodeIfPresent(Date.self, forKey: .startAt)
        evening = try c.decodeIfPresent(Bool.self, forKey: .evening) ?? false
        someday = try c.decodeIfPresent(Bool.self, forKey: .someday) ?? false
        remindAt = try c.decodeIfPresent(Date.self, forKey: .remindAt)
        recurrence = try c.decodeIfPresent(String.self, forKey: .recurrence)
        checklist = try c.decodeIfPresent([ChecklistItem].self, forKey: .checklist) ?? []
        orderKey = try c.decodeIfPresent(Double.self, forKey: .orderKey) ?? 0
    }

    var priorityLevel: Priority { Priority(rawValue: priority) ?? .none }
}

enum Priority: Int, CaseIterable, Identifiable, Sendable {
    case none = 0, low, medium, high
    var id: Int { rawValue }
    var title: String {
        switch self { case .none: "None"; case .low: "Low"; case .medium: "Medium"; case .high: "High" }
    }
    /// "!", "!!", "!!!" as Reminders shows them.
    var marks: String { String(repeating: "!", count: rawValue) }
}

/// The repeat rules the server accepts (docs-by-gitwork `nextOccurrence`).
enum Recurrence: Hashable, Sendable {
    case daily, weekdays, weekly, fortnightly, monthly, yearly
    case every(Int, Unit)

    enum Unit: String, CaseIterable, Sendable { case day, week, month }

    static let presets: [Recurrence] = [.daily, .weekdays, .weekly, .fortnightly, .monthly, .yearly]

    init?(rule: String?) {
        guard let rule else { return nil }
        switch rule {
        case "daily": self = .daily
        case "weekdays": self = .weekdays
        case "weekly": self = .weekly
        case "fortnightly": self = .fortnightly
        case "monthly": self = .monthly
        case "yearly": self = .yearly
        default:
            let p = rule.split(separator: ":")
            guard p.count == 3, p[0] == "every", let n = Int(p[1]), (1...365).contains(n), let u = Unit(rawValue: String(p[2])) else { return nil }
            self = .every(n, u)
        }
    }

    var rule: String {
        switch self {
        case .daily: "daily"
        case .weekdays: "weekdays"
        case .weekly: "weekly"
        case .fortnightly: "fortnightly"
        case .monthly: "monthly"
        case .yearly: "yearly"
        case .every(let n, let u): "every:\(n):\(u.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .daily: "Every day"
        case .weekdays: "Every weekday"
        case .weekly: "Every week"
        case .fortnightly: "Every 2 weeks"
        case .monthly: "Every month"
        case .yearly: "Every year"
        case .every(let n, let u): "Every \(n) \(u.rawValue)\(n == 1 ? "" : "s")"
        }
    }
}
