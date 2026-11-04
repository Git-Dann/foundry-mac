import Foundation
import Observation

/// One event from your Google Calendar, as Foundry reads it. Read-only.
struct CalendarEvent: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
    var meetLink: URL?
    var htmlLink: URL?
    var attendees: Int
}

/// The wire shape of `GET /api/backstage/calendar/events` (docs-by-gitwork). camelCase, as is.
struct CalendarEventsResponse: Decodable, Sendable {
    struct Event: Decodable, Sendable {
        var id: String
        var title: String
        var start: String
        var end: String
        var allDay: Bool
        var location: String?
        var meetLink: String?
        var htmlLink: String?
        var attendees: Int
    }
    var connected: Bool
    var reason: String?
    var events: [Event]

    /// All-day events come as calendar days ("2026-11-06"), read as local days; others are ISO times.
    static func date(_ raw: String, calendar: Calendar = .current) -> Date? {
        if raw.count == 10 {
            let parts = raw.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        return ISO8601DateParser.date(from: raw)
    }

    func appEvents() -> [CalendarEvent] {
        events.compactMap { e in
            guard let start = Self.date(e.start), let end = Self.date(e.end) else { return nil }
            return CalendarEvent(
                id: e.id, title: e.title, start: start, end: max(end, start), isAllDay: e.allDay,
                location: e.location, meetLink: Commitment.link(e.meetLink, base: Commitment.webBase),
                htmlLink: Commitment.link(e.htmlLink, base: Commitment.webBase), attendees: e.attendees
            )
        }
    }
}

/// Your calendar, read through Foundry (which already holds your Google sign-in), so there's no
/// separate permission to grant on the Mac. Weeks are cached in memory and re-read when shown.
@MainActor
@Observable
final class CalendarStore {
    enum Status: Equatable {
        case unknown
        case connected
        /// Foundry couldn't read the calendar, in its own words.
        case unavailable(String)
    }

    private(set) var status: Status = .unknown
    private(set) var isLoading = false
    private var cache: [String: [CalendarEvent]] = [:]

    @ObservationIgnored private let baseURL: @Sendable () async -> URL
    @ObservationIgnored private let token: @Sendable () async -> String?
    @ObservationIgnored private let network = NetworkClient()
    @ObservationIgnored private var loadedAt: [String: Date] = [:]

    init(baseURL: @escaping @Sendable () async -> URL, token: @escaping @Sendable () async -> String?) {
        self.baseURL = baseURL
        self.token = token
    }

    private static func key(_ from: Date, _ to: Date) -> String {
        "\(Int(from.timeIntervalSince1970))-\(Int(to.timeIntervalSince1970))"
    }

    func events(from: Date, to: Date) -> [CalendarEvent] { cache[Self.key(from, to)] ?? [] }

    /// Reads the range unless it was read in the last two minutes (or `force`).
    func load(from: Date, to: Date, force: Bool = false) async {
        let key = Self.key(from, to)
        #if DEBUG
        if isPreview { return }
        #endif
        if !force, let at = loadedAt[key], Date().timeIntervalSince(at) < 120 { return }
        guard let token = await token() else { return }
        isLoading = true
        defer { isLoading = false }
        var url = await baseURL().appending(path: "api/backstage/calendar/events")
        url.append(queryItems: [
            URLQueryItem(name: "from", value: ISO8601DateParser.string(from: from)),
            URLQueryItem(name: "to", value: ISO8601DateParser.string(from: to)),
        ])
        do {
            let response: CalendarEventsResponse = try await network.execute(
                APIRequest(url: url, headers: ["Authorization": "Bearer \(token)", "Accept": "application/json"])
            )
            loadedAt[key] = Date()
            if response.connected {
                cache[key] = response.appEvents()
                status = .connected
            } else {
                status = .unavailable(response.reason ?? "Foundry couldn't read your calendar.")
            }
        } catch let error as AppError {
            if case .http(404, _) = error {
                status = .unavailable("Your calendar isn't on this Foundry server yet.")
            } else if case .network = error {
                // Offline: keep what's cached and say nothing new.
            } else {
                status = .unavailable(error.localizedDescription)
            }
        } catch {
            status = .unavailable(error.localizedDescription)
        }
    }

    func clear() {
        cache = [:]; loadedAt = [:]; status = .unknown
    }

    #if DEBUG
    @ObservationIgnored private var isPreview = false

    func loadForPreview(_ events: [CalendarEvent], from: Date, to: Date) {
        isPreview = true
        cache[Self.key(from, to)] = events
        status = .connected
    }
    #endif
}
