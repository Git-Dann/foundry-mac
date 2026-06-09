import Foundation
import Observation

/// The native Foundry API surface. Builds authenticated `URLSession` requests (Bearer JWT),
/// decodes the bare-JSON responses, and maps HTTP 401 to a re-authentication prompt.
///
/// Runs on the main actor for simplicity (it reads the token + base URL from the observable
/// stores); the `await` network calls suspend without blocking the UI. No server secret is
/// ever attached — only the per-user JWT from the Keychain.
@MainActor
@Observable
final class FoundryAPIClient {
    private let environment: AppEnvironment
    private let auth: AuthStore
    private let network: NetworkClient

    init(environment: AppEnvironment, auth: AuthStore, network: NetworkClient = NetworkClient()) {
        self.environment = environment
        self.auth = auth
        self.network = network
    }

    // MARK: Request plumbing

    private func makeRequest(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil,
        authenticated: Bool = true
    ) throws -> APIRequest {
        var url = environment.baseURL
        for segment in path.split(separator: "/") {
            url.appendPathComponent(String(segment))
        }
        var request = APIRequest(url: url, method: method, queryItems: query, body: body)
        request.headers["Accept"] = "application/json"
        if authenticated {
            guard let token = auth.token else { throw AppError.notAuthenticated }
            request.headers["Authorization"] = "Bearer \(token)"
        }
        return request
    }

    private func send<T: Decodable>(_ request: APIRequest) async throws -> T {
        do {
            return try await network.execute(request)
        } catch let error as AppError {
            if error.isUnauthorized { auth.handleUnauthorized() }
            throw error
        }
    }

    private func sendNoContent(_ request: APIRequest) async throws {
        do {
            try await network.executeWithoutResponse(request)
        } catch let error as AppError {
            if error.isUnauthorized { auth.handleUnauthorized() }
            throw error
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do { return try JSONEncoder.foundry.encode(value) }
        catch { throw AppError.decoding("Couldn't encode the request: \(error.localizedDescription)") }
    }
}

// MARK: - Health

extension FoundryAPIClient {
    func health() async throws -> HealthStatus {
        try await send(makeRequest("api/health", authenticated: false))
    }
}

// MARK: - Proposals

extension FoundryAPIClient {
    func listProposals(
        search: String? = nil,
        status: DocumentStatus? = nil,
        documentType: DocumentType? = nil,
        sort: String? = nil
    ) async throws -> [ProposalListItem] {
        var query: [URLQueryItem] = []
        if let search, !search.isEmpty { query.append(.init(name: "search", value: search)) }
        if let status { query.append(.init(name: "status", value: status.rawValue)) }
        if let documentType { query.append(.init(name: "documentType", value: documentType.rawValue)) }
        if let sort { query.append(.init(name: "sort", value: sort)) }
        let response: ProposalListResponse = try await send(makeRequest("api/proposals", query: query))
        return response.proposals
    }

    func getProposal(id: String) async throws -> ProposalDetail {
        let response: ProposalDetailResponse = try await send(makeRequest("api/proposals/\(id)"))
        return response.proposal
    }

    @discardableResult
    func createProposal(_ input: ProposalCreateInput) async throws -> ProposalDetail {
        let request = try makeRequest("api/proposals", method: "POST", body: try encode(input))
        let response: ProposalDetailResponse = try await send(request)
        return response.proposal
    }

    @discardableResult
    func updateProposal(id: String, _ input: ProposalUpdateInput) async throws -> ProposalDetail {
        let request = try makeRequest("api/proposals/\(id)", method: "PATCH", body: try encode(input))
        let response: ProposalDetailResponse = try await send(request)
        return response.proposal
    }
}

// MARK: - Clients

extension FoundryAPIClient {
    func listClients(search: String? = nil, status: WorkspaceClientStatus? = nil) async throws -> [ClientListItem] {
        var query: [URLQueryItem] = []
        if let search, !search.isEmpty { query.append(.init(name: "search", value: search)) }
        if let status { query.append(.init(name: "status", value: status.rawValue)) }
        let response: ClientListResponse = try await send(makeRequest("api/clients", query: query))
        return response.clients
    }

    func getClient(slug: String) async throws -> ClientDetailResponse {
        try await send(makeRequest("api/clients/\(slug)"))
    }

    func createClient(_ input: ClientInput) async throws {
        try await sendNoContent(makeRequest("api/clients", method: "POST", body: try encode(input)))
    }

    func updateClient(slug: String, _ input: ClientInput) async throws {
        try await sendNoContent(makeRequest("api/clients/\(slug)", method: "PATCH", body: try encode(input)))
    }

    func setClientStatus(slug: String, status: WorkspaceClientStatus) async throws {
        let body = try encode(["status": status.rawValue])
        try await sendNoContent(makeRequest("api/clients/\(slug)/status", method: "POST", body: body))
    }

    func deleteClient(slug: String) async throws {
        try await sendNoContent(makeRequest("api/clients/\(slug)", method: "DELETE"))
    }
}

// MARK: - Rate card

extension FoundryAPIClient {
    func listRateCard(search: String? = nil, includeArchived: Bool = false) async throws -> [RateCardPerson] {
        var query: [URLQueryItem] = []
        if let search, !search.isEmpty { query.append(.init(name: "search", value: search)) }
        if includeArchived { query.append(.init(name: "includeArchived", value: "true")) }
        let response: RateCardListResponse = try await send(makeRequest("api/rate-card/people", query: query))
        return response.people
    }

    func createRatePerson(_ input: RateCardPersonCreateInput) async throws {
        try await sendNoContent(makeRequest("api/rate-card/people", method: "POST", body: try encode(input)))
    }

    func updateRatePerson(id: String, _ input: RateCardPersonUpdateInput) async throws {
        try await sendNoContent(makeRequest("api/rate-card/people/\(id)", method: "PATCH", body: try encode(input)))
    }

    func deleteRatePerson(id: String) async throws {
        try await sendNoContent(makeRequest("api/rate-card/people/\(id)", method: "DELETE"))
    }
}

// MARK: - CodeClear

extension FoundryAPIClient {
    func codeClearStats() async throws -> CodeClearStats {
        try await send(makeRequest("api/codeclear/stats"))
    }

    func listCandidates(
        query: String? = nil,
        status: PipelineStatus? = nil,
        tier: CodeClearTier? = nil,
        page: Int = 1,
        pageSize: Int = 30
    ) async throws -> CandidateListResponse {
        var items: [URLQueryItem] = [
            .init(name: "page", value: String(page)),
            .init(name: "pageSize", value: String(pageSize)),
        ]
        if let query, !query.isEmpty { items.append(.init(name: "q", value: query)) }
        if let status { items.append(.init(name: "status", value: status.rawValue)) }
        if let tier { items.append(.init(name: "tier", value: tier.rawValue)) }
        return try await send(makeRequest("api/codeclear/candidates", query: items))
    }
}
