import Foundation

/// A Google Calendar event time — either a timed `dateTime` (RFC3339) or an all-day `date` (yyyy-MM-dd).
struct GCalEventTime: Codable, Sendable {
    var dateTime: String?
    var date: String?
    var timeZone: String?

    var isAllDay: Bool { dateTime == nil && date != nil }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var resolvedDate: Date? {
        if let dateTime, let parsed = ISO8601DateParser.date(from: dateTime) { return parsed }
        if let date { return Self.dayFormatter.date(from: date) }
        return nil
    }
}

/// A Google Calendar event (the subset the native window renders + edits).
struct GCalEvent: Codable, Sendable, Identifiable {
    var id: String
    var summary: String?
    var description: String?
    var location: String?
    var start: GCalEventTime?
    var end: GCalEventTime?
    var htmlLink: String?
    var status: String?

    var title: String { summary?.nilIfEmpty ?? "(No title)" }
    var startDate: Date? { start?.resolvedDate }
    var isAllDay: Bool { start?.isAllDay ?? false }
    var isCancelled: Bool { status == "cancelled" }
}

struct GCalEventsResponse: Decodable, Sendable {
    let items: [GCalEvent]?
}

/// Write payload for creating/updating an event.
struct GCalEventInput: Encodable, Sendable {
    var summary: String
    var description: String?
    var location: String?
    var start: GCalEventTime
    var end: GCalEventTime
}
