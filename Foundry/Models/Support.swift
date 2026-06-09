import Foundation

// Care (client support). NOTE: the API wire format for these enums is lowercase / snake_case.

enum TicketStatus: String, Decodable, Sendable, CaseIterable, Identifiable {
    case open, inProgress = "in_progress", devReview = "dev_review", awaitingCustomer = "awaiting_customer", resolved
    case unknown
    var id: String { rawValue }
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TicketStatus(rawValue: raw) ?? .unknown
    }
    var label: String {
        switch self {
        case .open: return "Open"
        case .inProgress: return "In progress"
        case .devReview: return "Dev review"
        case .awaitingCustomer: return "Awaiting customer"
        case .resolved: return "Resolved"
        case .unknown: return "—"
        }
    }
    static var selectable: [TicketStatus] { [.open, .inProgress, .devReview, .awaitingCustomer, .resolved] }
}

enum TicketPriority: String, Decodable, Sendable {
    case urgent, high, normal, low, unknown
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TicketPriority(rawValue: raw) ?? .unknown
    }
    var label: String { self == .unknown ? "—" : rawValue.capitalized }
}

enum ConversationSentiment: String, Decodable, Sendable {
    case positive, neutral, negative, unknown
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ConversationSentiment(rawValue: raw) ?? .unknown
    }
}

enum MessageDirection: String, Decodable, Sendable {
    case inbound, outbound, unknown
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MessageDirection(rawValue: raw) ?? .unknown
    }
}

enum SupportSource: String, Decodable, Sendable {
    case gmail, reddit, instagram, youtube, discord, clickup, stripe, analytics, slack, email, unknown
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SupportSource(rawValue: raw) ?? .unknown
    }
    var label: String { self == .unknown ? "Other" : rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .gmail, .email: return "envelope"
        case .discord, .slack: return "bubble.left.and.bubble.right"
        case .reddit, .instagram, .youtube: return "globe"
        case .stripe: return "creditcard"
        case .clickup: return "checklist"
        case .analytics: return "chart.bar"
        case .unknown: return "questionmark.circle"
        }
    }
}

enum DraftActionStatus: String, Decodable, Sendable {
    case pendingApproval = "pending_approval", approved, rejected, sent, unknown
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DraftActionStatus(rawValue: raw) ?? .unknown
    }
    var label: String {
        switch self {
        case .pendingApproval: return "Pending approval"
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        case .sent: return "Sent"
        case .unknown: return "—"
        }
    }
}

enum DraftActionRisk: String, Decodable, Sendable {
    case low, medium, high, unknown
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DraftActionRisk(rawValue: raw) ?? .unknown
    }
    var label: String { self == .unknown ? "—" : rawValue.capitalized }
}

// MARK: - Models

struct SupportClient: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String
    let status: String?
    let supportDaysPerMonth: Int?
    let supportDaysUsed: Int?
    let unreadCount: Int?

    var isActive: Bool { (status ?? "active") == "active" }
}

struct SupportConversation: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let clientId: String
    let source: SupportSource
    let customerLabel: String
    let subject: String
    let preview: String
    let receivedAt: Date
    let unread: Bool
    let tags: [String]
    let sentiment: ConversationSentiment
    let ticketId: String?
}

struct SupportMessage: Decodable, Sendable, Identifiable {
    let id: String
    let conversationId: String
    let direction: MessageDirection
    let authorLabel: String
    let body: String
    let createdAt: Date
}

struct SupportTicket: Decodable, Sendable, Identifiable {
    let id: String
    let clientId: String
    let title: String
    let customerLabel: String?
    let status: TicketStatus
    let priority: TicketPriority
    let source: SupportSource
    let nextAction: String?
    let issueType: String?
    let updatedAt: Date
    let assignedTo: String?
    let resolvedAt: Date?
}

struct SupportDraftAction: Decodable, Sendable, Identifiable {
    let id: String
    let clientId: String
    let ticketId: String?
    let type: String
    let title: String
    let body: String
    let status: DraftActionStatus
    let risk: DraftActionRisk
}

struct SupportAuditLog: Decodable, Sendable, Identifiable {
    let id: String
    let actor: String?
    let action: String
    let target: String?
    let createdAt: Date
}

struct SupportDashboard: Decodable, Sendable {
    let clientCount: Int
    let openTicketCount: Int
    let recentConversations: [DashboardConversation]

    struct DashboardConversation: Decodable, Sendable, Identifiable {
        let id: String
        let clientId: String
        let source: SupportSource
        let customerLabel: String
        let subject: String
        let preview: String
        let receivedAt: Date
        let unread: Bool
        let sentiment: ConversationSentiment
        let client: SupportClient
    }
}

struct SupportAnalyticsSnapshot: Decodable, Sendable {
    let periodLabel: String
    let metrics: [Metric]

    struct Metric: Decodable, Sendable, Identifiable {
        let key: String
        let label: String
        let value: Double
        let previous: Double?
        let unit: String?
        let group: String?
        var id: String { key }

        /// Signed percentage change vs the previous period, when both are present and non-zero.
        var trendPct: Double? {
            guard let previous, previous != 0 else { return nil }
            return (value - previous) / abs(previous) * 100
        }
    }
}

// MARK: - Response envelopes

struct SupportClientsResponse: Decodable, Sendable { let clients: [SupportClient] }
struct SupportConversationsResponse: Decodable, Sendable { let conversations: [SupportConversation] }
struct SupportConversationResponse: Decodable, Sendable { let conversation: SupportConversation }
struct SupportMessagesResponse: Decodable, Sendable { let messages: [SupportMessage] }
struct SupportMessageResponse: Decodable, Sendable { let message: SupportMessage }
struct SupportDraftResponse: Decodable, Sendable { let draft: String }
struct SupportTicketsResponse: Decodable, Sendable { let tickets: [SupportTicket] }
struct SupportTicketResponse: Decodable, Sendable { let ticket: SupportTicket }
struct SupportDraftActionsResponse: Decodable, Sendable { let draftActions: [SupportDraftAction] }
struct SupportDraftActionResponse: Decodable, Sendable { let draftAction: SupportDraftAction }
struct SupportAuditLogsResponse: Decodable, Sendable { let logs: [SupportAuditLog] }
