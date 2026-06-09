import Foundation

// MARK: - Enums (lenient: unknown server values decode to `.unknown` rather than failing)

enum DocumentStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case draft = "DRAFT"
    case productSignOff = "PRODUCT_SIGN_OFF"
    case techSignOff = "TECH_SIGN_OFF"
    case inReview = "IN_REVIEW"
    case approved = "APPROVED"
    case sent = "SENT"
    case accepted = "ACCEPTED"
    case declined = "DECLINED"
    case archived = "ARCHIVED"
    case unknown = "UNKNOWN"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DocumentStatus(rawValue: raw) ?? .unknown
    }

    /// Values offered in a status picker (everything the user can set).
    static var selectable: [DocumentStatus] { allCases.filter { $0 != .unknown } }

    var label: String {
        switch self {
        case .draft: return "Draft"
        case .productSignOff: return "Product sign-off"
        case .techSignOff: return "Tech sign-off"
        case .inReview: return "In review"
        case .approved: return "Approved"
        case .sent: return "Sent"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .archived: return "Archived"
        case .unknown: return "—"
        }
    }
}

enum DocumentType: String, Codable, CaseIterable, Identifiable, Sendable {
    case proposal = "PROPOSAL"
    case sla = "SLA"
    case sow = "SOW"
    case msa = "MSA"
    case nda = "NDA"
    case co = "CO"
    case dsa = "DSA"
    case other = "OTHER"
    case unknown = "UNKNOWN"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DocumentType(rawValue: raw) ?? .unknown
    }

    static var selectable: [DocumentType] { allCases.filter { $0 != .unknown } }

    var label: String {
        switch self {
        case .proposal: return "Proposal"
        case .sla: return "SLA"
        case .sow: return "SOW"
        case .msa: return "MSA"
        case .nda: return "NDA"
        case .co: return "Change Order"
        case .dsa: return "DSA"
        case .other: return "Other"
        case .unknown: return "—"
        }
    }
}

// MARK: - List

/// `GET /api/proposals` → `{ proposals: [ProposalListItem] }`
struct ProposalListItem: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let clientName: String?
    let productName: String?
    let status: DocumentStatus
    let updatedAt: Date
    let templateName: String?
    let ownerName: String?
    let documentNumber: String?
    let documentType: DocumentType
    let labels: [String]
    let parentId: String?
}

struct ProposalListResponse: Codable, Sendable {
    let proposals: [ProposalListItem]
}

// MARK: - Detail

/// `GET /api/proposals/[id]` → `{ proposal: ProposalDetail }`
struct ProposalDetail: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let workspaceId: String
    let ownerId: String?
    let templateId: String?
    let documentType: DocumentType
    let status: DocumentStatus
    let title: String
    let productName: String?
    let clientName: String?
    let clientId: String?
    let linkedClientLogoUrl: String?
    let summary: String
    let version: String
    let documentNumber: String?
    let shareToken: String?
    let isShared: Bool
    let labels: [String]
    let parentId: String?
    let expiresAt: Date?
    let metadata: ProposalMetadata?
    let createdAt: Date
    let updatedAt: Date
    let sections: [ProposalSection]
    let costLineItems: [CostLineItem]
    let timelinePhases: [TimelinePhase]
    let links: [ProposalLink]
    let ctas: [ProposalCTA]

    /// Total of one-off cost line items (recurring shown separately in the UI).
    var oneOffTotal: Double { costLineItems.filter { $0.costKind == "ONE_OFF" }.reduce(0) { $0 + $1.subtotal } }
    var recurringTotal: Double { costLineItems.filter { $0.costKind == "RECURRING" }.reduce(0) { $0 + $1.subtotal } }
}

struct ProposalDetailResponse: Codable, Sendable {
    let proposal: ProposalDetail
}

struct ProposalMetadata: Codable, Sendable, Equatable {
    var client: String?
    var owner: String?
    var version: String?
    var productSignOff: Bool?
    var techSignOff: Bool?
    var approvalChecked: Bool?
}

struct ProposalSection: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let key: String
    let title: String
    let description: String?
    let sortOrder: Int
    let isVisible: Bool
    let data: JSONValue?
}

struct CostLineItem: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let category: String
    let itemName: String
    let description: String
    let quantity: Double
    let unitCost: Double
    let subtotal: Double
    let costKind: String
    let sortOrder: Int
}

struct TimelinePhase: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let duration: String
    let summary: String
    let deliverables: [String]
    let sortOrder: Int
    let viewMode: String
}

struct ProposalLink: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    let url: String
    let type: String
    let notes: String
    let sortOrder: Int
}

struct ProposalCTA: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let role: String
    let label: String
    let destination: String
    let destinationType: String
    let sortOrder: Int
}

// MARK: - Write inputs

/// `POST /api/proposals` body (`proposalCreateSchema`).
struct ProposalCreateInput: Encodable, Sendable {
    var title: String
    var clientName: String?
    var clientId: String?
    var productName: String?
    var templateId: String?
    var documentType: DocumentType?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(clientName, forKey: .clientName)
        try c.encodeIfPresent(clientId, forKey: .clientId)
        try c.encodeIfPresent(productName, forKey: .productName)
        try c.encodeIfPresent(templateId, forKey: .templateId)
        try c.encodeIfPresent(documentType, forKey: .documentType)
    }

    enum CodingKeys: String, CodingKey {
        case title, clientName, clientId, productName, templateId, documentType
    }
}

/// `PATCH /api/proposals/[id]` body (`proposalUpdateSchema`) — document-level fields only.
/// nil fields are omitted (left unchanged on the server). The rich section editor stays in
/// Foundry Web; native edits cover title/status/summary/client/product/version/labels.
struct ProposalUpdateInput: Encodable, Sendable {
    var title: String?
    var status: DocumentStatus?
    var productName: String?
    var clientName: String?
    var summary: String?
    var version: String?
    var labels: [String]?

    var hasChanges: Bool {
        title != nil || status != nil || productName != nil || clientName != nil
            || summary != nil || version != nil || labels != nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(productName, forKey: .productName)
        try c.encodeIfPresent(clientName, forKey: .clientName)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encodeIfPresent(version, forKey: .version)
        try c.encodeIfPresent(labels, forKey: .labels)
    }

    enum CodingKeys: String, CodingKey {
        case title, status, productName, clientName, summary, version, labels
    }
}
