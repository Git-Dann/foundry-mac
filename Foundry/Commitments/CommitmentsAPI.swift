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

private extension String {
    /// Server ids are cuids; anything else is percent-encoded rather than trusted into a path.
    var urlPathSafe: String {
        addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) ?? self
    }
}
