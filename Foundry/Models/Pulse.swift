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

/// The full server `llmAnalysis`, rendered natively (the report no longer opens in WebKit).
/// Every field is optional + leniently decoded so server-side drift never breaks the screen;
/// `projectClassification` is intentionally not decoded (internal routing data).
struct PulseAnalysis: Decodable, Sendable {
    let executiveSummary: String?
    let healthNarrative: String?
    let proposalHook: String?
    let strengths: [PulseStrength]?
    let criticalGaps: [PulseCriticalGap]?
    let buildOpportunities: [PulseOpportunity]?
    let scalingRoadmap: [PulseRoadmapPhase]?
    let techDebt: [PulseTechDebt]?
    let productionBlockers: [PulseBlocker]?
    let productionReadinessChecklist: [PulseReadinessItem]?
    let techStackAnalysis: PulseTechStackAnalysis?
}

struct PulseOpportunity: Decodable, Sendable, Identifiable {
    let title: String
    let description: String?
    let estimatedEffort: String?
    let businessValue: String?
    let category: String?
    var id: String { title }
}

struct PulseRoadmapPhase: Decodable, Sendable, Identifiable {
    let phase: String?
    let title: String
    let duration: String?
    let goals: [String]?
    var id: String { title }

    enum CodingKeys: String, CodingKey { case phase, title, duration, goals }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `phase` arrives as a number OR a string depending on the model's mood.
        if let number = try? c.decodeIfPresent(Int.self, forKey: .phase) {
            phase = String(number)
        } else {
            phase = (try? c.decodeIfPresent(String.self, forKey: .phase)) ?? nil
        }
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? "Phase"
        duration = try? c.decodeIfPresent(String.self, forKey: .duration)
        goals = try? c.decodeIfPresent([String].self, forKey: .goals)
    }
}

struct PulseTechDebt: Decodable, Sendable, Identifiable {
    let area: String
    let description: String?
    let severity: String?
    var id: String { area }
}

struct PulseBlocker: Decodable, Sendable, Identifiable {
    let category: String?
    let blocker: String
    let why: String?
    let recommendedService: String?
    let urgency: String?
    var id: String { blocker }
}

struct PulseReadinessItem: Decodable, Sendable, Identifiable {
    let category: String?
    let item: String
    let status: String?
    let notes: String?
    var id: String { item }

    var isReady: Bool { (status ?? "").lowercased().contains("ready") || (status ?? "").lowercased() == "pass" }
}

struct PulseTechStackAnalysis: Decodable, Sendable {
    let assessment: String?
    let detectedStack: [String]?
    let recommendations: [String]?
    let missingForProduction: [String]?
}

// MARK: Agent insights (code / deploy / browser) + discovery + competitors

struct PulseDiscoveryKit: Decodable, Sendable {
    struct WowFinding: Decodable, Sendable { let finding: String?; let impact: String? }
    struct Question: Decodable, Sendable, Identifiable {
        let question: String
        let context: String?
        let followUp: String?
        var id: String { question }
    }
    struct Objection: Decodable, Sendable, Identifiable {
        let objection: String
        let response: String?
        var id: String { objection }
    }
    struct PricingAnchor: Decodable, Sendable {
        let low: Double?
        let high: Double?
        let rationale: String?
    }

    let openingStatement: String?
    let wowFinding: WowFinding?
    let questions: [Question]?
    let anticipatedObjections: [Objection]?
    let pricingAnchor: PricingAnchor?
    let talkingPoints: [String]?
}

struct PulseCodeInsights: Decodable, Sendable {
    struct Vulnerability: Decodable, Sendable, Identifiable {
        let severity: String?
        let packageName: String?
        let description: String?
        var id: String { (packageName ?? "") + (description ?? "") }
    }
    let vulnerabilities: [Vulnerability]?
    let branchProtected: Bool?
    let requiresReviews: Bool?
    let prReviewRate: Double?
    let commitVelocity: Double?
    let uniqueContributors: Int?
}

struct PulseDeployInsights: Decodable, Sendable {
    let platform: String?
    let recentDeployments: Int?
    let failedDeployments: Int?
    let avgBuildMs: Double?
    let buildWarnings: [String]?
    let recentErrorPatterns: [String]?
}

struct PulseBrowserInsights: Decodable, Sendable {
    let performanceScore: Double?
    let accessibilityScore: Double?
    let seoScore: Double?
    let bestPracticesScore: Double?
    let lcp: Double?
    let cls: Double?
    let fcp: Double?
    let tbt: Double?
    let cruxCategory: String?
}

struct PulseCompetitorData: Decodable, Sendable {
    struct CompetitorScan: Decodable, Sendable, Identifiable {
        let url: String
        let healthScore: Int?
        let checksPass: Int?
        let checksWarn: Int?
        let checksFail: Int?
        let techStack: [String]?
        var id: String { url }
    }
    struct Comparison: Decodable, Sendable {
        let summary: String?
        let advantages: [String]?
        let gaps: [String]?
        let recommendation: String?
    }
    let scans: [CompetitorScan]?
    let comparison: Comparison?
}

/// Full scan detail — header, checks, the complete AI analysis, and every agent payload. The
/// report is rendered entirely natively.
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
    let discoveryKit: PulseDiscoveryKit?
    let codeInsights: PulseCodeInsights?
    let deployInsights: PulseDeployInsights?
    let browserInsights: PulseBrowserInsights?
    let competitorData: PulseCompetitorData?
    let aiError: String?
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
