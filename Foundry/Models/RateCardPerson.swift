import Foundation

enum RateBillingPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case day = "DAY"
    case week = "WEEK"
    case month = "MONTH"
    case unknown = "UNKNOWN"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RateBillingPeriod(rawValue: raw) ?? .unknown
    }

    static var selectable: [RateBillingPeriod] { [.day, .week, .month] }

    var label: String {
        switch self {
        case .day: return "per day"
        case .week: return "per week"
        case .month: return "per month"
        case .unknown: return "—"
        }
    }
}

/// `GET /api/rate-card/people` → `{ people: [RateCardPerson] }`
struct RateCardPerson: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let area: String
    let sourceRate: Double
    let sourceCurrencyCode: String
    let billingPeriod: RateBillingPeriod
    let archivedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    var isArchived: Bool { archivedAt != nil }
}

struct RateCardListResponse: Codable, Sendable {
    let people: [RateCardPerson]
}

/// `POST /api/rate-card/people` (`rateCardPersonCreateSchema`).
struct RateCardPersonCreateInput: Encodable, Sendable {
    var name: String
    var area: String
    var sourceRate: Double
    var sourceCurrencyCode: String
    var billingPeriod: RateBillingPeriod
}

/// `PATCH /api/rate-card/people/[id]` (`rateCardPersonUpdateSchema`) — at least one field.
struct RateCardPersonUpdateInput: Encodable, Sendable {
    var name: String?
    var area: String?
    var sourceRate: Double?
    var sourceCurrencyCode: String?
    var billingPeriod: RateBillingPeriod?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(area, forKey: .area)
        try c.encodeIfPresent(sourceRate, forKey: .sourceRate)
        try c.encodeIfPresent(sourceCurrencyCode, forKey: .sourceCurrencyCode)
        try c.encodeIfPresent(billingPeriod, forKey: .billingPeriod)
    }

    enum CodingKeys: String, CodingKey {
        case name, area, sourceRate, sourceCurrencyCode, billingPeriod
    }
}
