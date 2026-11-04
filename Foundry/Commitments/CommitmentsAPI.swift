import Foundation

/// The six Commitments endpoints (docs-by-gitwork `docs/commitments.md`).
///
/// A protocol so the store can be tested against an in-memory fake, and so the offline queue
/// never needs a real network to be exercised.
protocol CommitmentsService: Sendable {
    func list() async throws -> CommitmentsResponse
    func create(_ new: NewCommitment) async throws -> Commitment
    func update(id: String, _ patch: CommitmentPatch) async throws -> Commitment
    func delete(id: String) async throws
    func sync() async throws -> CommitmentSyncResult
    func updateSettings(_ settings: CommitmentSettings) async throws -> CommitmentSettings
    /// Board tasks assigned to this person (`GET /api/tasks?assigneeId=`).
    func boardTasks(assigneeId: String) async throws -> [BoardTaskDTO]
    /// Ticks, reopens or re-dates a board task (`PATCH /api/tasks/<id>`). `dueDate` is a day.
    func updateBoardTask(id: String, status: String?, dueDate: CommitmentPatch.Field<String>?) async throws -> BoardTaskDTO
    func createList(name: String, color: String?, symbol: String?, area: String?) async throws -> TodoList
    func updateList(_ list: TodoList) async throws -> TodoList
    func deleteList(id: String) async throws
    func reorder(ids: [String]) async throws
}

/// Talks to `https://foundry.gitwork.co.uk/api/backstage/commitments` with the person's Bearer JWT.
struct CommitmentsAPI: CommitmentsService {
    let baseURL: @Sendable () async -> URL
    let token: @Sendable () async -> String?
    var network = NetworkClient()

    private struct CommitmentEnvelope: Decodable { var commitment: Commitment }
    private struct SettingsEnvelope: Decodable { var settings: CommitmentSettings }
    private struct SyncEnvelope: Decodable { var result: CommitmentSyncResult }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> APIRequest {
        guard let token = await token() else { throw AppError.notAuthenticated }
        return APIRequest(
            url: await baseURL().appending(path: "api/backstage/commitments" + path),
            method: method,
            headers: ["Authorization": "Bearer \(token)", "Accept": "application/json"],
            body: body
        )
    }

    func list() async throws -> CommitmentsResponse {
        try await network.execute(try await request(""))
    }

    func create(_ new: NewCommitment) async throws -> Commitment {
        let r: CommitmentEnvelope = try await network.execute(try await request("", method: "POST", body: try new.jsonBody()))
        return r.commitment
    }

    func update(id: String, _ patch: CommitmentPatch) async throws -> Commitment {
        let r: CommitmentEnvelope = try await network.execute(
            try await request("/\(id.urlPathSafe)", method: "PATCH", body: try patch.jsonBody())
        )
        return r.commitment
    }

    func delete(id: String) async throws {
        try await network.executeWithoutResponse(try await request("/\(id.urlPathSafe)", method: "DELETE"))
    }

    func sync() async throws -> CommitmentSyncResult {
        let r: SyncEnvelope = try await network.execute(try await request("/sync", method: "POST", body: Data("{}".utf8)))
        return r.result
    }

    private struct ListEnvelope: Decodable { var list: TodoList }

    func createList(name: String, color: String?, symbol: String?, area: String?) async throws -> TodoList {
        var body: [String: Any] = ["name": name]
        body["color"] = color ?? NSNull()
        body["symbol"] = symbol ?? NSNull()
        body["area"] = area ?? NSNull()
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let r: ListEnvelope = try await network.execute(try await request("/lists", method: "POST", body: data))
        return r.list
    }

    func updateList(_ list: TodoList) async throws -> TodoList {
        let body: [String: Any] = [
            "name": list.name, "color": list.color ?? NSNull(), "symbol": list.symbol ?? NSNull(),
            "area": list.area ?? NSNull(), "orderKey": list.orderKey,
        ]
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let r: ListEnvelope = try await network.execute(try await request("/lists/\(list.id.urlPathSafe)", method: "PATCH", body: data))
        return r.list
    }

    func deleteList(id: String) async throws {
        try await network.executeWithoutResponse(try await request("/lists/\(id.urlPathSafe)", method: "DELETE"))
    }

    func reorder(ids: [String]) async throws {
        let data = try JSONSerialization.data(withJSONObject: ["ids": ids], options: [])
        try await network.executeWithoutResponse(try await request("/reorder", method: "POST", body: data))
    }

    func updateSettings(_ s: CommitmentSettings) async throws -> CommitmentSettings {
        let body = try JSONSerialization.data(withJSONObject: [
            "gmailEnabled": s.gmailEnabled,
            "slackEnabled": s.slackEnabled,
            "meetingsEnabled": s.meetingsEnabled,
            "calendarEnabled": s.calendarEnabled,
        ], options: [.sortedKeys])
        let r: SettingsEnvelope = try await network.execute(try await request("/settings", method: "PUT", body: body))
        return r.settings
    }
}

extension CommitmentsAPI {
    private func tasksRequest(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) async throws -> APIRequest {
        guard let token = await token() else { throw AppError.notAuthenticated }
        var url = await baseURL().appending(path: "api/tasks" + path)
        if !query.isEmpty { url.append(queryItems: query) }
        return APIRequest(
            url: url,
            method: method,
            headers: ["Authorization": "Bearer \(token)", "Accept": "application/json"],
            body: body
        )
    }

    func boardTasks(assigneeId: String) async throws -> [BoardTaskDTO] {
        try await network.execute(try await tasksRequest("", query: [
            URLQueryItem(name: "assigneeId", value: assigneeId),
            URLQueryItem(name: "doneWithinDays", value: "14"),
        ]))
    }

    func updateBoardTask(id: String, status: String?, dueDate: CommitmentPatch.Field<String>?) async throws -> BoardTaskDTO {
        var body: [String: Any] = [:]
        if let status { body["status"] = status }
        switch dueDate {
        case .set(let day): body["dueDate"] = day
        case .clear: body["dueDate"] = NSNull()
        case nil: break
        }
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return try await network.execute(try await tasksRequest("/\(id.urlPathSafe)", method: "PATCH", body: data))
    }
}

private extension String {
    /// Server ids are cuids; anything else is percent-encoded rather than trusted into a path.
    var urlPathSafe: String {
        addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) ?? self
    }
}
