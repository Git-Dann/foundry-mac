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

// MARK: - AI cost (Super-Admin)

extension FoundryAPIClient {
    /// Real billed AI spend (today + month-to-date). The route is Super-Admin-only, so a 403
    /// (or any throw) means "spend unavailable on this account" — callers surface nothing rather
    /// than an error. No per-module/token breakdown yet (top-line spend only).
    func aiCost() async throws -> AiCostSummary {
        try await send(makeRequest("api/admin/ai-cost"))
    }
}

// MARK: - Pulse

extension FoundryAPIClient {
    func listPulseScans(clientId: String? = nil) async throws -> [PulseScanSummary] {
        var query: [URLQueryItem] = []
        if let clientId { query.append(.init(name: "clientId", value: clientId)) }
        let response: PulseScanListResponse = try await send(makeRequest("api/pulse/scans", query: query))
        return response.scans
    }

    func getPulseScan(id: String) async throws -> PulseScanDetail {
        let response: PulseScanResponse = try await send(makeRequest("api/pulse/scans/\(id)"))
        return response.scan
    }

    @discardableResult
    func createPulseScan(_ input: PulseScanInput) async throws -> PulseScanDetail {
        let request = try makeRequest("api/pulse/scans", method: "POST", body: try encode(input))
        let response: PulseScanResponse = try await send(request)
        return response.scan
    }

    func cancelPulseScan(id: String) async throws {
        try await sendNoContent(makeRequest("api/pulse/scans/\(id)/cancel"))
    }

    func retryPulseScan(id: String) async throws {
        try await sendNoContent(makeRequest("api/pulse/scans/\(id)/retry"))
    }

    func reanalysePulseScan(id: String) async throws {
        try await sendNoContent(makeRequest("api/pulse/scans/\(id)/reanalyse"))
    }

    func listPulseMonitors() async throws -> [PulseMonitor] {
        let response: PulseMonitorListResponse = try await send(makeRequest("api/pulse/monitors"))
        return response.monitors
    }

    @discardableResult
    func createPulseMonitor(_ input: PulseMonitorInput) async throws -> PulseMonitor {
        let request = try makeRequest("api/pulse/monitors", method: "POST", body: try encode(input))
        let response: PulseMonitorResponse = try await send(request)
        return response.monitor
    }

    func setPulseMonitorActive(id: String, isActive: Bool) async throws {
        let body = try encode(["isActive": isActive])
        try await sendNoContent(makeRequest("api/pulse/monitors/\(id)", method: "PATCH", body: body))
    }

    func deletePulseMonitor(id: String) async throws {
        try await sendNoContent(makeRequest("api/pulse/monitors/\(id)", method: "DELETE"))
    }

    func listPulseLeads() async throws -> [PulseLead] {
        let response: PulseLeadListResponse = try await send(makeRequest("api/pulse/leads"))
        return response.leads
    }

    func importPulseLead(id: String) async throws {
        try await sendNoContent(makeRequest("api/pulse/leads/\(id)/import", method: "POST"))
    }

    /// Live SSE stream of a running scan. Yields each `data:` JSON payload; the caller decodes a
    /// `PulseStreamEnvelope` and merges deltas. Reads the per-user JWT (never a server secret).
    func pulseScanStream(id: String) throws -> AsyncThrowingStream<String, Error> {
        guard let token = auth.token else { throw AppError.notAuthenticated }
        var url = environment.baseURL
        for segment in "api/pulse/scans/\(id)/stream".split(separator: "/") {
            url.appendPathComponent(String(segment))
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return SSEClient.dataLines(for: request)
    }
}

// MARK: - Docs analytics + versions + comments

extension FoundryAPIClient {
    /// Per-document link-tracking analytics (visitors, dwell heatmap, conversion, device/geo).
    func documentAnalytics(id: String) async throws -> DocumentAnalytics {
        let response: DocumentAnalyticsResponse = try await send(makeRequest("api/documents/\(id)/analytics"))
        return response.analytics
    }

    /// Cross-document funnel + leaderboards. `/api/documents/analytics` is a static segment that
    /// out-prioritises `/api/documents/[id]`.
    func documentsAnalytics(documentType: DocumentType? = nil, days: Int? = nil) async throws -> DocsAnalyticsSummary {
        var query: [URLQueryItem] = []
        if let documentType { query.append(.init(name: "documentType", value: documentType.rawValue)) }
        if let days { query.append(.init(name: "days", value: String(days))) }
        let response: DocsAnalyticsResponse = try await send(makeRequest("api/documents/analytics", query: query))
        return response.analytics
    }

    func documentVersions(id: String) async throws -> [DocumentVersion] {
        let response: DocumentVersionsResponse = try await send(makeRequest("api/documents/\(id)/versions"))
        return response.versions
    }

    func documentComments(id: String) async throws -> [DocumentComment] {
        let response: DocumentCommentsResponse = try await send(makeRequest("api/documents/\(id)/comments"))
        return response.comments
    }
}

// MARK: - Tasks · feature blocks · milestones · team (Portal)
// These routes return bare arrays/objects (not enveloped).

extension FoundryAPIClient {
    func listTasks(clientId: String, status: TaskStatus? = nil) async throws -> [TaskItem] {
        var query: [URLQueryItem] = [.init(name: "clientId", value: clientId)]
        if let status { query.append(.init(name: "status", value: status.rawValue)) }
        return try await send(makeRequest("api/tasks", query: query))
    }

    func getTask(id: String) async throws -> TaskItemDetail {
        try await send(makeRequest("api/tasks/\(id)"))
    }

    @discardableResult
    func createTask(_ input: TaskInput) async throws -> TaskItem {
        try await send(makeRequest("api/tasks", method: "POST", body: try encode(input)))
    }

    @discardableResult
    func updateTask(id: String, _ input: TaskUpdate) async throws -> TaskItem {
        try await send(makeRequest("api/tasks/\(id)", method: "PATCH", body: try encode(input)))
    }

    func deleteTask(id: String) async throws {
        try await sendNoContent(makeRequest("api/tasks/\(id)", method: "DELETE"))
    }

    @discardableResult
    func moveTask(id: String, status: TaskStatus, orderKey: Double) async throws -> TaskItem {
        struct Body: Encodable { let status: String; let orderKey: Double }
        let body = try encode(Body(status: status.rawValue, orderKey: orderKey))
        return try await send(makeRequest("api/tasks/\(id)/move", method: "POST", body: body))
    }

    @discardableResult
    func addTaskComment(id: String, body text: String) async throws -> TaskComment {
        struct Body: Encodable { let body: String }
        let body = try encode(Body(body: text))
        return try await send(makeRequest("api/tasks/\(id)/comments", method: "POST", body: body))
    }

    func listFeatureBlocks(clientId: String) async throws -> [FeatureBlock] {
        try await send(makeRequest("api/feature-blocks", query: [.init(name: "clientId", value: clientId)]))
    }

    @discardableResult
    func createFeatureBlock(_ input: FeatureBlockInput) async throws -> FeatureBlock {
        try await send(makeRequest("api/feature-blocks", method: "POST", body: try encode(input)))
    }

    func deleteFeatureBlock(id: String) async throws {
        try await sendNoContent(makeRequest("api/feature-blocks/\(id)", method: "DELETE"))
    }

    func listMilestones(clientId: String) async throws -> [Milestone] {
        try await send(makeRequest("api/milestones", query: [.init(name: "clientId", value: clientId)]))
    }

    @discardableResult
    func createMilestone(_ input: MilestoneInput) async throws -> Milestone {
        try await send(makeRequest("api/milestones", method: "POST", body: try encode(input)))
    }

    func deleteMilestone(id: String) async throws {
        try await sendNoContent(makeRequest("api/milestones/\(id)", method: "DELETE"))
    }

    func listTeamMembers() async throws -> [WorkspaceMember] {
        try await send(makeRequest("api/team/members"))
    }
}

// MARK: - Meetings (Scribe)

extension FoundryAPIClient {
    func listMeetings(clientSlug: String, query: String? = nil) async throws -> MeetingsResponse {
        var q: [URLQueryItem] = []
        if let query, !query.isEmpty { q.append(.init(name: "q", value: query)) }
        return try await send(makeRequest("api/clients/\(clientSlug)/meetings", query: q))
    }

    func getMeeting(clientSlug: String, id: String) async throws -> Meeting {
        let response: MeetingResponse = try await send(makeRequest("api/clients/\(clientSlug)/meetings/\(id)"))
        return response.meeting
    }

    @discardableResult
    func ingestMeeting(clientSlug: String, _ input: MeetingIngestInput) async throws -> Meeting {
        let request = try makeRequest("api/clients/\(clientSlug)/meetings/ingest", method: "POST", body: try encode(input))
        let response: MeetingResponse = try await send(request)
        return response.meeting
    }

    @discardableResult
    func setMeetingActionDone(clientSlug: String, meetingId: String, actionItemId: String, done: Bool) async throws -> Meeting {
        struct Body: Encodable { let actionItemId: String; let done: Bool }
        let body = try encode(Body(actionItemId: actionItemId, done: done))
        let response: MeetingResponse = try await send(makeRequest("api/clients/\(clientSlug)/meetings/\(meetingId)", method: "PATCH", body: body))
        return response.meeting
    }
}
