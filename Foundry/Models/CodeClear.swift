import Foundation

enum PipelineStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case sourced = "SOURCED"
    case invited = "INVITED"
    case assessmentInProgress = "ASSESSMENT_IN_PROGRESS"
    case codeclearComplete = "CODECLEAR_COMPLETE"
    case placed = "PLACED"
    case recheckDue = "RECHECK_DUE"
    case unknown = "UNKNOWN"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PipelineStatus(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .sourced: return "Sourced"
        case .invited: return "Invited"
        case .assessmentInProgress: return "Assessment in progress"
        case .codeclearComplete: return "CodeClear complete"
        case .placed: return "Placed"
        case .recheckDue: return "Recheck due"
        case .unknown: return "—"
        }
    }
}

enum CodeClearTier: String, Codable, CaseIterable, Identifiable, Sendable {
    case tier1 = "TIER_1"
    case tier2 = "TIER_2"
    case tier3 = "TIER_3"
    case unknown = "UNKNOWN"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CodeClearTier(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .tier1: return "Tier 1"
        case .tier2: return "Tier 2"
        case .tier3: return "Tier 3"
        case .unknown: return "—"
        }
    }
}

// MARK: - Stats

/// `GET /api/codeclear/stats`
struct CodeClearStats: Codable, Sendable, Equatable {
    let total: Int
    let byStatus: [StatusCount]
    let avgThis: Double?
    let avgLast: Double?
    let passRateThis: Double?
    let recheckDue: Int

    struct StatusCount: Codable, Sendable, Equatable, Identifiable {
        let status: PipelineStatus
        let count: Int
        var id: String { status.rawValue }
    }
}

// MARK: - Candidates

/// `GET /api/codeclear/candidates` → `{ items, meta, facets }`
struct CandidateListResponse: Codable, Sendable {
    let items: [Candidate]
    let meta: Meta
    let facets: Facets

    struct Meta: Codable, Sendable, Equatable {
        let page: Int
        let pageSize: Int
        let total: Int
        let totalPages: Int
    }

    struct Facets: Codable, Sendable, Equatable {
        let stacks: [String]
    }
}

/// A pragmatic subset of the (large) candidate payload — the fields the native list + detail
/// surface. Unmodeled response keys are ignored by Codable.
struct Candidate: Codable, Identifiable, Sendable, Equatable, Hashable {
    let id: String
    let name: String
    let githubHandle: String
    let email: String?
    let primaryStack: String
    let techStacks: [String]
    let location: String?
    let bio: String?
    let status: PipelineStatus
    let effectiveTier: CodeClearTier
    let avatarUrl: String?
    let linkedinUrl: String?
    let yearsExperience: Int?
    let hourlyRate: Double?
    let currency: String?
    let updatedAt: Date
    let score: CandidateScore?
    let currentClients: [CandidateClient]

    struct CandidateClient: Codable, Sendable, Equatable, Hashable, Identifiable {
        let id: String?
        let name: String
        let slug: String?
        var identity: String { id ?? slug ?? name }
    }
}

struct CandidateScore: Codable, Sendable, Equatable, Hashable {
    let technicalDepth: Double?
    let codeQuality: Double?
    let aiFluency: Double?
    let deliveryReadiness: Double?
    let identityConfidence: String?
    let overallScore: Double?
}

// MARK: - Candidate detail extras (GET /api/codeclear/candidates/[id] → { candidate })

/// The richer surfaces the detail endpoint adds on top of the list item (placements, notes,
/// latest GitHub analysis, checks). The header/profile/score still come from the list `Candidate`.
struct CandidateDetail: Decodable, Sendable, Identifiable {
    let id: String
    let placements: [CodeClearPlacement]
    let notes: [CodeClearNote]
    let latestGitHubAnalysis: GitHubAnalysisRun?
    let checks: [CodeClearCheck]
}

struct CandidateDetailResponse: Decodable, Sendable { let candidate: CandidateDetail }

struct CodeClearPlacement: Decodable, Sendable, Identifiable {
    let id: String
    let clientName: String
    let projectName: String
    let startDate: Date?
    let endDate: Date?
    let allocationPercent: Int?
    let notes: String?
}

struct CodeClearNote: Decodable, Sendable, Identifiable {
    let id: String
    let body: String
    let createdBy: String?
    let createdAt: Date
}

struct CodeClearNoteResponse: Decodable, Sendable { let note: CodeClearNote }

struct GitHubAnalysisRun: Decodable, Sendable, Identifiable {
    let id: String
    let status: String
    let llmSummary: String?
    let redFlags: [String]?
    let completedAt: Date?
}

struct CodeClearCheck: Decodable, Sendable, Identifiable {
    let id: String
    let category: String
    let label: String
    let status: String
    let detail: String?
    let sortOrder: Int

    /// Maps the PASS/WARN/FAIL/SKIPPED string onto the shared Pulse check status for icon/tint.
    var checkStatus: PulseCheckStatus { PulseCheckStatus(rawValue: status) ?? .unknown }
}
