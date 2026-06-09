import Foundation

enum WorkspaceClientStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case pendingReview = "PENDING_REVIEW"
    case active = "ACTIVE"
    case archived = "ARCHIVED"
    case unknown = "UNKNOWN"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WorkspaceClientStatus(rawValue: raw) ?? .unknown
    }

    static var selectable: [WorkspaceClientStatus] { [.pendingReview, .active, .archived] }

    var label: String {
        switch self {
        case .pendingReview: return "Pending review"
        case .active: return "Active"
        case .archived: return "Archived"
        case .unknown: return "—"
        }
    }
}

/// `GET /api/clients` → `{ clients: [ClientListItem] }`
struct ClientListItem: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let slug: String
    let logoUrl: String?
    let createdAt: Date
    let updatedAt: Date
    let proposalCount: Int
    let status: WorkspaceClientStatus
    let googleDriveFolderUrl: String?
    let clickupUrl: String?
    let hasCareClient: Bool
    let repoUrls: [String]
}

struct ClientListResponse: Codable, Sendable {
    let clients: [ClientListItem]
}

// MARK: - Detail (we model the fields the native UI shows; extra response keys are ignored)

/// `GET /api/clients/[slug]` → `{ client, platforms, designs, proposals, … }`
struct ClientDetailResponse: Codable, Sendable {
    let client: ClientDetail
    let platforms: [ClientPlatform]
    let designs: [ClientDesign]
    let proposals: [ProposalListItem]
}

struct ClientDetail: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let slug: String
    let logoUrl: String?
    let createdAt: Date
    let updatedAt: Date
    let proposalCount: Int
    let status: WorkspaceClientStatus
    let googleDriveFolderUrl: String?
    let clickupUrl: String?
    let hasCareClient: Bool
    let repoUrls: [String]
    let website: String?
    let addressLine1: String?
    let addressLine2: String?
    let city: String?
    let county: String?
    let postcode: String?
    let country: String?
    let notes: String?
    let primaryContactName: String?
    let primaryContactEmail: String?
    let primaryContactPhone: String?
    let invoiceEmail: String?
    let slackChannelId: String?
    let legalCompanyName: String?
    let companyNumber: String?
    let vatNumber: String?
}

struct ClientPlatform: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let platformType: String?
    let url: String?
    let stagingUrl: String?
    let repoUrl: String?
    let notes: String?
    let previewImageUrl: String?
}

struct ClientDesign: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let url: String?
    let notes: String?
    let previewImageUrl: String?
}

// MARK: - Write inputs

/// `POST /api/clients` (`clientCreateSchema`) and `PATCH /api/clients/[slug]` (`clientUpdateSchema`).
/// nil fields are omitted. For create, `name` must be present.
struct ClientInput: Encodable, Sendable {
    var name: String?
    var website: String?
    var primaryContactName: String?
    var primaryContactEmail: String?
    var primaryContactPhone: String?
    var notes: String?
    var addressLine1: String?
    var city: String?
    var postcode: String?
    var country: String?
    var legalCompanyName: String?
    var companyNumber: String?
    var vatNumber: String?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(website, forKey: .website)
        try c.encodeIfPresent(primaryContactName, forKey: .primaryContactName)
        try c.encodeIfPresent(primaryContactEmail, forKey: .primaryContactEmail)
        try c.encodeIfPresent(primaryContactPhone, forKey: .primaryContactPhone)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(addressLine1, forKey: .addressLine1)
        try c.encodeIfPresent(city, forKey: .city)
        try c.encodeIfPresent(postcode, forKey: .postcode)
        try c.encodeIfPresent(country, forKey: .country)
        try c.encodeIfPresent(legalCompanyName, forKey: .legalCompanyName)
        try c.encodeIfPresent(companyNumber, forKey: .companyNumber)
        try c.encodeIfPresent(vatNumber, forKey: .vatNumber)
    }

    enum CodingKeys: String, CodingKey {
        case name, website, primaryContactName, primaryContactEmail, primaryContactPhone
        case notes, addressLine1, city, postcode, country, legalCompanyName, companyNumber, vatNumber
    }
}
