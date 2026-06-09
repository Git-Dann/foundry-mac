import Foundation

/// Two-way Google Calendar REST client (calendar/v3), authorised with the per-user Google access
/// token from `GoogleAuthStore`. Read + create/update/delete events.
@MainActor
final class GoogleCalendarService {
    private let auth: GoogleAuthStore
    private let base = "https://www.googleapis.com/calendar/v3"

    init(auth: GoogleAuthStore) { self.auth = auth }

    func listEvents(calendarId: String = "primary", from: Date, to: Date) async throws -> [GCalEvent] {
        var components = URLComponents(string: "\(base)/calendars/\(calendarId)/events")!
        components.queryItems = [
            .init(name: "timeMin", value: ISO8601DateParser.string(from: from)),
            .init(name: "timeMax", value: ISO8601DateParser.string(from: to)),
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy", value: "startTime"),
            .init(name: "maxResults", value: "250"),
        ]
        let token = try await auth.validAccessToken()
        let data = try await execute(request(components.url!, method: "GET", token: token))
        let response = try JSONDecoder().decode(GCalEventsResponse.self, from: data)
        return (response.items ?? []).filter { !$0.isCancelled }
    }

    @discardableResult
    func createEvent(calendarId: String = "primary", _ input: GCalEventInput) async throws -> GCalEvent {
        try await write(path: "/calendars/\(calendarId)/events", method: "POST", body: input)
    }

    @discardableResult
    func updateEvent(calendarId: String = "primary", id: String, _ input: GCalEventInput) async throws -> GCalEvent {
        try await write(path: "/calendars/\(calendarId)/events/\(id)", method: "PATCH", body: input)
    }

    func deleteEvent(calendarId: String = "primary", id: String) async throws {
        let token = try await auth.validAccessToken()
        _ = try await execute(request(URL(string: "\(base)/calendars/\(calendarId)/events/\(id)")!, method: "DELETE", token: token))
    }

    // MARK: Plumbing

    private func write<Body: Encodable>(path: String, method: String, body: Body) async throws -> GCalEvent {
        let token = try await auth.validAccessToken()
        var req = request(URL(string: base + path)!, method: method, token: token)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let data = try await execute(req)
        return try JSONDecoder().decode(GCalEvent.self, from: data)
    }

    private func request(_ url: URL, method: String, token: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    @discardableResult
    private func execute(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError.network("No response from Google.") }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw AppError.http(status: 401, message: "Google session expired — reconnect.") }
            let message = String(data: data, encoding: .utf8).map { String($0.prefix(300)) } ?? ""
            throw AppError.http(status: http.statusCode, message: message)
        }
        return data
    }
}
