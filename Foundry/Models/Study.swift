import Foundation

// Study — AI-powered user research (multi-agent persona interviews).

// MARK: - Enums (lenient: unknown raw values never fail the decode)

enum StudyStatus: String, Decodable, Sendable {
    case draft = "DRAFT"
    case planGenerating = "PLAN_GENERATING"
    case planReady = "PLAN_READY"
    case running = "RUNNING"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StudyStatus(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .draft: return "Draft"
        case .planGenerating: return "Generating plan"
        case .planReady: return "Plan ready"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .unknown: return "—"
        }
    }

    /// The server is actively working — the detail screen should follow the SSE stream.
    var isActive: Bool { self == .planGenerating || self == .running }
}

enum StudySessionStatus: String, Decodable, Sendable {
    case pending = "PENDING", running = "RUNNING", completed = "COMPLETED", failed = "FAILED", unknown
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StudySessionStatus(rawValue: raw) ?? .unknown
    }
    var label: String { self == .unknown ? "—" : rawValue.capitalized }
}

// MARK: - Personas

struct StudyPersona: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let shortName: String?
    let description: String?
    let color: String?
    let techComfort: String?
}

// MARK: - Studies

struct StudyListItem: Decodable, Sendable, Identifiable {
    let id: String
    let title: String
    let problemStatement: String
    let status: StudyStatus
    let sessionMode: String
    let selectedPersonaIds: [String]
    let sessionCount: Int
    let completedSessionCount: Int
    let workspaceClientName: String?
    let createdAt: Date
    let updatedAt: Date
}

struct StudyPlanQuestion: Decodable, Sendable, Identifiable {
    let id: String
    let text: String
    let personaIds: [String]
    let turnType: String?
    let orderIndex: Int
    let rationale: String?
}

struct StudyPlan: Decodable, Sendable {
    let id: String
    let notes: String?
    let status: String?
    let questions: [StudyPlanQuestion]
}

/// One persona answer inside an interview exchange.
struct StudyResponse: Decodable, Sendable {
    let spoken: String?
    let sentiment: String?
    let painPoints: [String]?
    let delights: [String]?
    let confusionPoints: [String]?
}

struct StudyExchange: Decodable, Sendable {
    let question: String?
    let response: StudyResponse?
    let isFollowUp: Bool?
    let depth: Int?
}

struct StudyTurn: Decodable, Sendable {
    struct Synthesis: Decodable, Sendable {
        let summary: String?
        let keyInsights: [String]?
    }
    let questionText: String?
    let exchanges: [StudyExchange]?
    let synthesis: Synthesis?
}

struct StudySessionSynthesis: Decodable, Sendable {
    let overallSentiment: String?
    let keyThemes: [String]?
    let topPainPoints: [String]?
    let topDelights: [String]?
    let notableQuotes: [String]?
    let summary: String?
}

struct StudyTranscript: Decodable, Sendable {
    let turns: [StudyTurn]?
    let synthesis: StudySessionSynthesis?
}

struct StudySession: Decodable, Sendable, Identifiable {
    let id: String
    let personaId: String
    let personaName: String
    let mode: String?
    let status: StudySessionStatus
    let transcriptData: StudyTranscript?
    let startedAt: Date?
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, personaId, personaName, mode, status, transcriptData, startedAt, completedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        personaId = (try? c.decode(String.self, forKey: .personaId)) ?? "—"
        personaName = (try? c.decode(String.self, forKey: .personaName)) ?? "Persona"
        mode = try? c.decodeIfPresent(String.self, forKey: .mode) ?? nil
        status = (try? c.decode(StudySessionStatus.self, forKey: .status)) ?? .unknown
        // AI-generated payload — never let a drifted transcript shape fail the whole study.
        transcriptData = (try? c.decodeIfPresent(StudyTranscript.self, forKey: .transcriptData)) ?? nil
        startedAt = (try? c.decodeIfPresent(Date.self, forKey: .startedAt)) ?? nil
        completedAt = (try? c.decodeIfPresent(Date.self, forKey: .completedAt)) ?? nil
    }
}

// MARK: - Report

struct StudyReportPayload: Decodable, Sendable {
    struct Theme: Decodable, Sendable, Identifiable {
        let theme: String
        let description: String?
        let personaIds: [String]?
        var id: String { theme }
    }
    struct PersonaFinding: Decodable, Sendable, Identifiable {
        let personaId: String?
        let personaName: String?
        let summary: String?
        let topInsights: [String]?
        var id: String { personaId ?? personaName ?? UUID().uuidString }
    }
    struct Recommendation: Decodable, Sendable, Identifiable {
        let title: String
        let rationale: String?
        let priority: String?
        var id: String { title }
    }

    let executiveSummary: String?
    let keyFindings: [String]?
    let themes: [Theme]?
    let perPersonaFindings: [PersonaFinding]?
    let recommendations: [Recommendation]?
    let openQuestions: [String]?
}

struct StudyReportEnvelope: Decodable, Sendable {
    let payload: StudyReportPayload?

    enum CodingKeys: String, CodingKey { case payload }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        payload = (try? c.decodeIfPresent(StudyReportPayload.self, forKey: .payload)) ?? nil
    }
}

// MARK: - Full study

struct StudyRecord: Decodable, Sendable, Identifiable {
    let id: String
    let title: String
    let problemStatement: String
    let researchGoals: [String]
    let status: StudyStatus
    let sessionMode: String
    let selectedPersonaIds: [String]
    let workspaceClientName: String?
    let plan: StudyPlan?
    let sessions: [StudySession]
    let report: StudyReportEnvelope?
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - Inputs + envelopes

struct StudyCreateInput: Encodable, Sendable {
    var title: String
    var problemStatement: String
    var researchGoals: [String]
    var sessionMode: String
    var selectedPersonaIds: [String]
}

struct StudyListResponse: Decodable, Sendable { let studies: [StudyListItem] }
struct StudyResponse2: Decodable, Sendable { let study: StudyRecord }
struct StudyPersonasResponse: Decodable, Sendable { let personas: [StudyPersona] }

/// One decoded `data:` payload from /api/study/studies/[id]/stream:
/// `{type:"state", study:{…}}` per tick, then `{type:"complete"}`.
struct StudyStreamEnvelope: Decodable, Sendable {
    let type: String
    let study: StudyRecord?

    enum CodingKeys: String, CodingKey { case type, study }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? ""
        study = (try? c.decodeIfPresent(StudyRecord.self, forKey: .study)) ?? nil
    }
}
