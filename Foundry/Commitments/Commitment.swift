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

    enum State: String, Codable, Sendable, CaseIterable {
        case suggested, open, done, dismissed

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            // An unknown state is shown as done rather than failing the whole list.
            self = State(rawValue: raw) ?? .done
        }
    }

    enum Source: String, Codable, Sendable {
        case manual, gmail, slack, meeting, calendar, unknown

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
            case .unknown: "circle.dotted"
            }
        }
    }

    var isLocalOnly: Bool { id.hasPrefix(Commitment.localPrefix) }
    static let localPrefix = "local-"

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
        return status.message
    }
}

struct CommitmentsResponse: Codable, Sendable {
    var commitments: [Commitment]
    var settings: CommitmentSettings
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

    var isEmpty: Bool {
        title == nil && notes == nil && dueAt == nil && counterpart == nil && state == nil && snoozedUntil == nil
    }

    /// Later edits win, field by field. Used to fold queued offline edits together.
    func merged(with later: CommitmentPatch) -> CommitmentPatch {
        CommitmentPatch(
            title: later.title ?? title,
            notes: later.notes ?? notes,
            dueAt: later.dueAt ?? dueAt,
            counterpart: later.counterpart ?? counterpart,
            state: later.state ?? state,
            snoozedUntil: later.snoozedUntil ?? snoozedUntil
        )
    }

    func applied(to c: Commitment, now: Date) -> Commitment {
        var c = c
        if let title { c.title = title.value ?? c.title }
        if let notes { c.notes = notes.value }
        if let dueAt { c.dueAt = dueAt.value }
        if let counterpart { c.counterpart = counterpart.value }
        if let snoozedUntil { c.snoozedUntil = snoozedUntil.value }
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
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
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

    func jsonBody() throws -> Data {
        var body: [String: Any] = ["title": title]
        if let dueAt { body["dueAt"] = ISO8601DateParser.string(from: dueAt) }
        if let notes, !notes.isEmpty { body["notes"] = notes }
        if let counterpart, !counterpart.isEmpty { body["counterpart"] = counterpart }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
}
