import Foundation

// Backstage — internal ops: leave + expenses.

enum LeaveType: String, Decodable, Sendable, CaseIterable, Identifiable {
    case annual = "ANNUAL", sick = "SICK", unpaid = "UNPAID", other = "OTHER", unknown
    var id: String { rawValue }
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LeaveType(rawValue: raw) ?? .unknown
    }
    var label: String { self == .unknown ? "Leave" : rawValue.capitalized }
}

enum LeaveStatus: String, Decodable, Sendable {
    case pending = "PENDING", approved = "APPROVED", rejected = "REJECTED", cancelled = "CANCELLED", unknown
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LeaveStatus(rawValue: raw) ?? .unknown
    }
    var label: String { self == .unknown ? "—" : rawValue.capitalized }
}

enum ExpenseStatus: String, Decodable, Sendable {
    case submitted = "SUBMITTED", approved = "APPROVED", rejected = "REJECTED", reimbursed = "REIMBURSED", unknown
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExpenseStatus(rawValue: raw) ?? .unknown
    }
    var label: String { self == .unknown ? "—" : rawValue.capitalized }
}

enum ExpenseCategory: String, Decodable, Sendable, CaseIterable, Identifiable {
    case travel = "TRAVEL", equipment = "EQUIPMENT", software = "SOFTWARE", meals = "MEALS", accommodation = "ACCOMMODATION", other = "OTHER"
    case unknown
    var id: String { rawValue }
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExpenseCategory(rawValue: raw) ?? .unknown
    }
    var label: String { self == .unknown ? "Other" : rawValue.capitalized }
}

struct BackstageUserRef: Decodable, Sendable { let id: String; let name: String; let avatarUrl: String? }
struct BackstageActorRef: Decodable, Sendable { let id: String; let name: String }

struct LeaveRequest: Decodable, Sendable, Identifiable {
    let id: String
    let user: BackstageUserRef
    let type: LeaveType
    let startDate: String   // may be full ISO or bare yyyy-MM-dd
    let endDate: String
    let halfDayStart: Bool
    let halfDayEnd: Bool
    let workingDays: Double
    let reason: String?
    let status: LeaveStatus
    let approvedBy: BackstageActorRef?
    let rejectionNote: String?
    let createdAt: Date

    var dateRange: String {
        startDate == endDate ? Formatters.day(startDate) : "\(Formatters.day(startDate)) – \(Formatters.day(endDate))"
    }
}

struct LeaveAllowance: Decodable, Sendable {
    let year: Int
    let allocated: Double
    let used: Double
    let pending: Double
    let remaining: Double
}

struct Expense: Decodable, Sendable, Identifiable {
    let id: String
    let user: BackstageUserRef
    let amount: Double
    let currency: String
    let category: ExpenseCategory
    let vendor: String?
    let occurredOn: String
    let notes: String?
    let hasReceipt: Bool
    let status: ExpenseStatus
    let reviewedBy: BackstageActorRef?
    let reviewNote: String?
    let createdAt: Date

    var amountText: String { Formatters.currency(amount, code: currency) }
}

// MARK: - Inputs

struct LeaveRequestInput: Encodable, Sendable {
    var type: LeaveType
    var startDate: String
    var endDate: String
    var halfDayStart: Bool?
    var halfDayEnd: Bool?
    var reason: String?

    enum CodingKeys: String, CodingKey { case type, startDate, endDate, halfDayStart, halfDayEnd, reason }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type.rawValue, forKey: .type)
        try c.encode(startDate, forKey: .startDate)
        try c.encode(endDate, forKey: .endDate)
        try c.encodeIfPresent(halfDayStart, forKey: .halfDayStart)
        try c.encodeIfPresent(halfDayEnd, forKey: .halfDayEnd)
        try c.encodeIfPresent(reason, forKey: .reason)
    }
}

struct ExpenseInput: Encodable, Sendable {
    var amount: Double
    var currency: String
    var category: ExpenseCategory
    var vendor: String?
    var occurredOn: String
    var notes: String?

    enum CodingKeys: String, CodingKey { case amount, currency, category, vendor, occurredOn, notes }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(amount, forKey: .amount)
        try c.encode(currency, forKey: .currency)
        try c.encode(category.rawValue, forKey: .category)
        try c.encodeIfPresent(vendor, forKey: .vendor)
        try c.encode(occurredOn, forKey: .occurredOn)
        try c.encodeIfPresent(notes, forKey: .notes)
    }
}
