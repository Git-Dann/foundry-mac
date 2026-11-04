import Foundation

/// One promise. Mirrors `CommitmentDTO` in docs-by-gitwork (`src/types/commitments.ts`).
///
/// ⚠️ The API is camelCase. These property names ARE the wire keys, and nothing in this app may
/// apply a snake_case key strategy (the iOS app broke that way: docs-by-gitwork CLAUDE.md §54).
struct Commitment: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var notes: String?
    var dueAt: Date?
    var state: State
    var source: Source
    var counterpart: String?
    /// The words a suggestion was read from. This is the evidence for the promise.
    var quote: String?
    var evidenceLabel: String?
    var evidenceUrl: String?
    var evidenceAt: Date?
    var reason: String?
    var snoozedUntil: Date?
    var doneAt: Date?
    var createdAt: Date
    var updatedAt: Date
    /// Board tasks only: the task's own status on the board (TODO, DOING, IN_REVIEW…), kept so
    /// reopening a ticked task puts it back where it was. Never sent by the commitments API.
    var boardStatus: String?

    // Planning fields (docs-by-gitwork: lists, tags, priority, checklists, repeating to-dos).
    // Older servers don't send them, so each has a default and decoding never requires them.
    var listId: String? = nil
    var tags: [String] = []
    var priority: Int = 0
    /// The day you plan to do it ("When"), as opposed to `dueAt`, the deadline.
    var startAt: Date? = nil
    var evening: Bool = false
    var someday: Bool = false
    var remindAt: Date? = nil
    var recurrence: String? = nil
    var checklist: [ChecklistItem] = []
    var orderKey: Double = 0

    enum CodingKeys: String, CodingKey {
        case id, title, notes, dueAt, state, source, counterpart, quote, evidenceLabel, evidenceUrl, evidenceAt, reason,
             snoozedUntil, doneAt, createdAt, updatedAt, boardStatus,
             listId, tags, priority, startAt, evening, someday, remindAt, recurrence, checklist, orderKey
    }

    enum State: String, Codable, Sendable, CaseIterable {
        case suggested, open, done, dismissed

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            // An unknown state is shown as done rather than failing the whole list.
            self = State(rawValue: raw) ?? .done
        }
    }

    enum Source: String, Codable, Sendable {
        case manual, gmail, slack, meeting, calendar, board, unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Source(rawValue: raw) ?? .unknown
        }

        var label: String {
            switch self {
            case .manual: "Added by you"
            case .gmail: "Email"
            case .slack: "Slack"
            case .meeting: "Meeting notes"
            case .calendar: "Calendar"
            case .board: "Board"
            case .unknown: "Foundry"
            }
        }

        var symbol: String {
            switch self {
            case .manual: "pencil"
            case .gmail: "envelope"
            case .slack: "number"
            case .meeting: "text.bubble"
            case .calendar: "calendar"
            case .board: "rectangle.split.3x1"
            case .unknown: "circle.dotted"
            }
        }
    }

    var isLocalOnly: Bool { id.hasPrefix(Commitment.localPrefix) }
    static let localPrefix = "local-"

    /// A Foundry board task assigned to you, shown in the same lists as your own to-dos.
    var isBoardTask: Bool { id.hasPrefix(Commitment.boardPrefix) }
    static let boardPrefix = "task:"
    var boardTaskId: String? { isBoardTask ? String(id.dropFirst(Commitment.boardPrefix.count)) : nil }

    /// The Foundry host relative links resolve against (meeting notes link to `/app/portal/…`).
    /// Set from `AppEnvironment` at launch.
    nonisolated(unsafe) static var webBase = URL(string: "https://foundry.gitwork.co.uk")!

    var evidenceLink: URL? { Commitment.link(evidenceUrl, base: Commitment.webBase) }

    /// Only web links open: an absolute http(s) URL, or a path on the Foundry host.
    static func link(_ raw: String?, base: URL) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if raw.hasPrefix("/") && !raw.hasPrefix("//") {
            return URL(string: raw, relativeTo: base)?.absoluteURL
        }
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil
        else { return nil }
        return url
    }

    func isSnoozed(at now: Date) -> Bool {
        guard let snoozedUntil else { return false }
        return snoozedUntil > now
    }
}

struct CommitmentSourceStatus: Codable, Hashable, Sendable {
    var ok: Bool
    var message: String
    var at: Date?
}

struct CommitmentSettings: Codable, Hashable, Sendable {
    var gmailEnabled: Bool
    var slackEnabled: Bool
    var meetingsEnabled: Bool
    var calendarEnabled: Bool
    var lastSyncedAt: Date?
    var syncing: Bool
    var sourceStatus: [String: CommitmentSourceStatus]
    var slackConnected: Bool

    static let empty = CommitmentSettings(
        gmailEnabled: false, slackEnabled: false, meetingsEnabled: true, calendarEnabled: true,
        lastSyncedAt: nil, syncing: false, sourceStatus: [:], slackConnected: false
    )

    /// The four switchable sources, in display order, with the `sourceStatus` key for each.
    enum Toggle: String, CaseIterable, Identifiable, Sendable {
        case gmail, slack, meeting, calendar
        var id: String { rawValue }

        var title: String {
            switch self {
            case .gmail: "Sent email"
            case .slack: "Slack"
            case .meeting: "Meeting notes"
            case .calendar: "Calendar"
            }
        }

        var detail: String {
            switch self {
            case .gmail: "Reads only what you wrote in email you sent. Off until you turn it on."
            case .slack: "Reads your own messages in client channels you can see."
            case .meeting: "Open action items from meetings you attended."
            case .calendar: "A follow-up after meetings with people outside Gitwork."
            }
        }

        var symbol: String { Commitment.Source(rawValue: rawValue)?.symbol ?? "circle" }

        /// What this app reads. Email and Slack are NOT read with AI here: what Foundry already
        /// collects from Slack shows in the Foundry feed instead, with no AI and no credit used.
        static let offered: [Toggle] = [.meeting, .calendar]
    }

    func isOn(_ toggle: Toggle) -> Bool {
        switch toggle {
        case .gmail: gmailEnabled
        case .slack: slackEnabled
        case .meeting: meetingsEnabled
        case .calendar: calendarEnabled
        }
    }

    mutating func set(_ toggle: Toggle, _ on: Bool) {
        switch toggle {
        case .gmail: gmailEnabled = on
        case .slack: slackEnabled = on
        case .meeting: meetingsEnabled = on
        case .calendar: calendarEnabled = on
        }
    }

    /// A failed source's own words, shown under its switch. Nil while it is working.
    func problem(for toggle: Toggle) -> String? {
        guard isOn(toggle), let status = sourceStatus[toggle.rawValue], !status.ok else { return nil }
        return SourceProblem.plain(status.message)
    }
}

struct CommitmentsResponse: Codable, Sendable {
    var commitments: [Commitment]
    var settings: CommitmentSettings
    var lists: [TodoList] = []
    /// Whether this server has lists, tags, priority, repeats… (it sends `lists` when it does).
    /// An older server refuses those fields outright, so the app must not send them.
    var supportsPlanning = true

    init(commitments: [Commitment], settings: CommitmentSettings, lists: [TodoList] = [], supportsPlanning: Bool = true) {
        self.commitments = commitments; self.settings = settings; self.lists = lists; self.supportsPlanning = supportsPlanning
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        commitments = try c.decode([Commitment].self, forKey: .commitments)
        settings = try c.decode(CommitmentSettings.self, forKey: .settings)
        lists = try c.decodeIfPresent([TodoList].self, forKey: .lists) ?? []
        supportsPlanning = c.contains(.lists)
    }

    enum CodingKeys: String, CodingKey { case commitments, settings, lists }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(commitments, forKey: .commitments)
        try c.encode(settings, forKey: .settings)
        try c.encode(lists, forKey: .lists)
    }
}

struct CommitmentSyncResult: Codable, Sendable {
    var status: String
    var added: Int
    var sources: [String: CommitmentSourceStatus]
}

/// A change to one commitment. Only the fields that are set are sent. `.clear` sends JSON null.
struct CommitmentPatch: Equatable, Sendable, Codable {
    enum Field<Value: Equatable & Sendable & Codable>: Equatable, Sendable, Codable {
        case set(Value)
        case clear
    }

    var title: Field<String>?
    var notes: Field<String>?
    var dueAt: Field<Date>?
    var counterpart: Field<String>?
    var state: Commitment.State?
    var snoozedUntil: Field<Date>?
    var listId: Field<String>? = nil
    var tags: [String]? = nil
    var priority: Int? = nil
    var startAt: Field<Date>? = nil
    var evening: Bool? = nil
    var someday: Bool? = nil
    var remindAt: Field<Date>? = nil
    var recurrence: Field<String>? = nil
    var checklist: [ChecklistItem]? = nil
    var orderKey: Double? = nil

    var isEmpty: Bool {
        title == nil && notes == nil && dueAt == nil && counterpart == nil && state == nil && snoozedUntil == nil
            && listId == nil && tags == nil && priority == nil && startAt == nil && evening == nil && someday == nil
            && remindAt == nil && recurrence == nil && checklist == nil && orderKey == nil
    }

    /// Later edits win, field by field. Used to fold queued offline edits together.
    func merged(with later: CommitmentPatch) -> CommitmentPatch {
        CommitmentPatch(
            title: later.title ?? title,
            notes: later.notes ?? notes,
            dueAt: later.dueAt ?? dueAt,
            counterpart: later.counterpart ?? counterpart,
            state: later.state ?? state,
            snoozedUntil: later.snoozedUntil ?? snoozedUntil,
            listId: later.listId ?? listId,
            tags: later.tags ?? tags,
            priority: later.priority ?? priority,
            startAt: later.startAt ?? startAt,
            evening: later.evening ?? evening,
            someday: later.someday ?? someday,
            remindAt: later.remindAt ?? remindAt,
            recurrence: later.recurrence ?? recurrence,
            checklist: later.checklist ?? checklist,
            orderKey: later.orderKey ?? orderKey
        )
    }

    func applied(to c: Commitment, now: Date) -> Commitment {
        var c = c
        if let title { c.title = title.value ?? c.title }
        if let notes { c.notes = notes.value }
        if let dueAt { c.dueAt = dueAt.value }
        if let counterpart { c.counterpart = counterpart.value }
        if let snoozedUntil { c.snoozedUntil = snoozedUntil.value }
        if let listId { c.listId = listId.value }
        if let tags { c.tags = tags }
        if let priority { c.priority = priority }
        if let startAt {
            c.startAt = startAt.value
            if c.startAt != nil { c.someday = false }
        }
        if let evening { c.evening = evening }
        if let someday {
            c.someday = someday
            if someday { c.startAt = nil; c.evening = false }
        }
        if let remindAt { c.remindAt = remindAt.value }
        if let recurrence { c.recurrence = recurrence.value }
        if let checklist { c.checklist = checklist }
        if let orderKey { c.orderKey = orderKey }
        if let state {
            c.state = state
            c.doneAt = state == .done ? (c.doneAt ?? now) : nil
        }
        c.updatedAt = now
        return c
    }

    /// The request body. Built by hand so the key names are exactly the API's camelCase ones.
    func jsonBody() throws -> Data {
        var body: [String: Any] = [:]
        func put<V>(_ key: String, _ field: Field<V>?, _ encode: (V) -> Any) {
            guard let field else { return }
            switch field {
            case .set(let v): body[key] = encode(v)
            case .clear: body[key] = NSNull()
            }
        }
        put("title", title) { $0 }
        put("notes", notes) { $0 }
        put("dueAt", dueAt) { ISO8601DateParser.string(from: $0) }
        put("counterpart", counterpart) { $0 }
        put("snoozedUntil", snoozedUntil) { ISO8601DateParser.string(from: $0) }
        if let state { body["state"] = state.rawValue }
        put("listId", listId) { $0 }
        if let tags { body["tags"] = tags }
        if let priority { body["priority"] = priority }
        put("startAt", startAt) { ISO8601DateParser.string(from: $0) }
        if let evening { body["evening"] = evening }
        if let someday { body["someday"] = someday }
        put("remindAt", remindAt) { ISO8601DateParser.string(from: $0) }
        put("recurrence", recurrence) { $0 }
        if let checklist { body["checklist"] = checklist.map { ["id": $0.id, "text": $0.text, "done": $0.done] } }
        if let orderKey { body["orderKey"] = orderKey }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
}

extension CommitmentPatch {
    /// The same edit with the planning fields removed, for a server that doesn't have them.
    var withoutPlanning: CommitmentPatch {
        CommitmentPatch(title: title, notes: notes, dueAt: dueAt, counterpart: counterpart, state: state, snoozedUntil: snoozedUntil)
    }
}

extension NewCommitment {
    var withoutPlanning: NewCommitment {
        NewCommitment(title: title, dueAt: dueAt, notes: notes, counterpart: counterpart)
    }
}

extension CommitmentPatch.Field {
    var value: Value? {
        if case .set(let v) = self { return v }
        return nil
    }
}

/// A new commitment typed in by the person.
struct NewCommitment: Equatable, Sendable, Codable {
    var title: String
    var dueAt: Date?
    var notes: String?
    var counterpart: String?
    var listId: String? = nil
    var tags: [String] = []
    var priority: Int = 0
    var startAt: Date? = nil
    var evening: Bool = false
    var someday: Bool = false
    var remindAt: Date? = nil
    var recurrence: String? = nil

    func jsonBody() throws -> Data {
        var body: [String: Any] = ["title": title]
        if let dueAt { body["dueAt"] = ISO8601DateParser.string(from: dueAt) }
        if let notes, !notes.isEmpty { body["notes"] = notes }
        if let counterpart, !counterpart.isEmpty { body["counterpart"] = counterpart }
        if let listId { body["listId"] = listId }
        if !tags.isEmpty { body["tags"] = tags }
        if priority != 0 { body["priority"] = priority }
        if let startAt { body["startAt"] = ISO8601DateParser.string(from: startAt) }
        if evening { body["evening"] = true }
        if someday { body["someday"] = true }
        if let remindAt { body["remindAt"] = ISO8601DateParser.string(from: remindAt) }
        if let recurrence { body["recurrence"] = recurrence }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
}
