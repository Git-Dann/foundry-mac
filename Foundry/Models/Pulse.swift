import Foundation

// MARK: - Enums

enum PulseInputType: String, Codable, Sendable, CaseIterable, Identifiable {
    case url = "URL"
    case githubRepo = "GITHUB_REPO"
    case freeText = "FREE_TEXT"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PulseInputType(rawValue: raw) ?? .url
    }

    var label: String {
        switch self {
        case .url: return "Website"
        case .githubRepo: return "GitHub repo"
        case .freeText: return "Description"
        }
    }
}

enum PulseScanStatus: String, Decodable, Sendable {
    case pending = "PENDING"
    case running = "RUNNING"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PulseScanStatus(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .pending: return "Queued"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .unknown: return "—"
        }
    }

    var isTerminal: Bool { self == .completed || self == .failed || self == .cancelled }
    var isRunning: Bool { self == .running || self == .pending }
}

enum PulseCheckStatus: String, Decodable, Sendable {
    case pass = "PASS"
    case warn = "WARN"
    case fail = "FAIL"
    case skipped = "SKIPPED"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PulseCheckStatus(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .pass: return "Pass"
        case .warn: return "Warn"
        case .fail: return "Fail"
        case .skipped: return "Skipped"
        case .unknown: return "—"
        }
    }
}

// MARK: - Scan models

struct PulseScanSummary: Decodable, Identifiable, Sendable {
    let id: String
    let projectName: String
    let inputType: PulseInputType
    let inputUrl: String?
    let inputGithubRepo: String?
    let clientName: String?
    let status: PulseScanStatus
    let healthScore: Int?
    let generatedProposalId: String?
    let createdAt: Date
    let updatedAt: Date

    /// What was scanned, for a one-line subtitle.
    var target: String {
        inputUrl ?? inputGithubRepo ?? inputType.label
    }
}

struct PulseScanCheck: Decodable, Identifiable, Sendable {
    let id: String
    let category: String
    let checkKey: String?
    let label: String
    let status: PulseCheckStatus
    let detail: String?
    let evidence: String?
    let sortOrder: Int
}

struct PulseStrength: Decodable, Sendable, Identifiable {
    let title: String
    let detail: String
    var id: String { title }
}

struct PulseCriticalGap: Decodable, Sendable, Identifiable {
    let gap: String
    let impact: String
    let category: String?
    let urgency: String?
    var id: String { gap }
}

/// The slice of the (large) server `llmAnalysis` the native detail renders. Extra keys in the
/// payload (classification, roadmap, tech debt, blockers, …) are intentionally not decoded — the
/// full visual report is opened in the WebKit pane instead.
struct PulseAnalysis: Decodable, Sendable {
    let executiveSummary: String?
    let healthNarrative: String?
    let proposalHook: String?
    let strengths: [PulseStrength]?
    let criticalGaps: [PulseCriticalGap]?
}

/// Lean scan detail: enough for the native screen (header + checks + analysis essentials). The
/// heavy nested agent payloads (discoveryKit, codeInsights, deployInsights, competitorData, …)
/// are deliberately omitted and surfaced via the embedded full report.
struct PulseScanDetail: Decodable, Identifiable, Sendable {
    let id: String
    let projectName: String
    let inputType: PulseInputType
    let inputUrl: String?
    let inputGithubRepo: String?
    let inputDescription: String?
    let clientName: String?
    let status: PulseScanStatus
    let healthScore: Int?
    let previousHealthScore: Int?
    let techStack: [String]?
    let llmAnalysis: PulseAnalysis?
    let checks: [PulseScanCheck]
    let shareToken: String?
    let isShared: Bool?
    let errorCode: String?
    let errorMessage: String?
    let generatedProposalId: String?
}

/// POST /api/pulse/scans body. Custom encoding omits nil fields (the web Zod schema treats them
/// as optional/undefined, not null).
struct PulseScanInput: Encodable, Sendable {
    var projectName: String
    var inputType: PulseInputType
    var inputUrl: String?
    var inputGithubRepo: String?
    var inputDescription: String?
    var clientId: String?

    enum CodingKeys: String, CodingKey {
        case projectName, inputType, inputUrl, inputGithubRepo, inputDescription, clientId
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(projectName, forKey: .projectName)
        try c.encode(inputType, forKey: .inputType)
        try c.encodeIfPresent(inputUrl, forKey: .inputUrl)
        try c.encodeIfPresent(inputGithubRepo, forKey: .inputGithubRepo)
        try c.encodeIfPresent(inputDescription, forKey: .inputDescription)
        try c.encodeIfPresent(clientId, forKey: .clientId)
    }
}

// MARK: - Monitors

struct PulseMonitor: Decodable, Identifiable, Sendable {
    let id: String
    let projectName: String
    let inputType: PulseInputType
    let inputUrl: String?
    let inputGithubRepo: String?
    let lastHealthScore: Int?
    let alertThreshold: Int
    let isActive: Bool
    let webhookUrl: String?

    var target: String { inputUrl ?? inputGithubRepo ?? inputType.label }
}

struct PulseMonitorInput: Encodable, Sendable {
    var projectName: String
    var inputType: PulseInputType
    var inputUrl: String?
    var inputGithubRepo: String?
    var alertThreshold: Int?

    enum CodingKeys: String, CodingKey {
        case projectName, inputType, inputUrl, inputGithubRepo, alertThreshold
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(projectName, forKey: .projectName)
        try c.encode(inputType, forKey: .inputType)
        try c.encodeIfPresent(inputUrl, forKey: .inputUrl)
        try c.encodeIfPresent(inputGithubRepo, forKey: .inputGithubRepo)
        try c.encodeIfPresent(alertThreshold, forKey: .alertThreshold)
    }
}

// MARK: - Leads

struct PulseLead: Decodable, Identifiable, Sendable {
    let id: String
    let email: String
    let targetUrl: String
    let healthScore: Int?
    let importedScanId: String?
    let createdAt: Date

    var isImported: Bool { importedScanId != nil }
}

// MARK: - SSE stream

/// One decoded `data:` payload from /api/pulse/scans/[id]/stream. The `type` field discriminates:
/// "checks" (new checks), "meta" (scalar scan state), "complete" (terminal).
struct PulseStreamEnvelope: Decodable, Sendable {
    let type: String
    let checks: [PulseScanCheck]?
    let scan: PulseStreamMeta?
    let totalChecks: Int?
}

struct PulseStreamMeta: Decodable, Sendable {
    let status: PulseScanStatus?
    let healthScore: Int?
    let previousHealthScore: Int?
    let checksCompletedAt: String?
    let completedAt: String?
    let errorCode: String?
    let errorMessage: String?
}

// MARK: - Response envelopes

struct PulseScanListResponse: Decodable, Sendable { let scans: [PulseScanSummary] }
struct PulseScanResponse: Decodable, Sendable { let scan: PulseScanDetail }
struct PulseMonitorListResponse: Decodable, Sendable { let monitors: [PulseMonitor] }
struct PulseMonitorResponse: Decodable, Sendable { let monitor: PulseMonitor }
struct PulseLeadListResponse: Decodable, Sendable { let leads: [PulseLead] }
