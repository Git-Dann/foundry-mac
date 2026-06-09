import Foundation

// NOTE: named `TaskItem`, not `Task` — `Task` is Swift Concurrency's type.

// MARK: - Enums

enum TaskStatus: String, Decodable, Sendable, CaseIterable, Identifiable {
    case backlog = "BACKLOG"
    case todo = "TODO"
    case doing = "DOING"
    case inReview = "IN_REVIEW"
    case done = "DONE"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TaskStatus(rawValue: raw) ?? .backlog
    }

    var label: String {
        switch self {
        case .backlog: return "Backlog"
        case .todo: return "To Do"
        case .doing: return "Doing"
        case .inReview: return "In Review"
        case .done: return "Done"
        }
    }
}

enum TaskPriority: String, Decodable, Sendable, CaseIterable, Identifiable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TaskPriority(rawValue: raw) ?? .medium
    }

    var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

// MARK: - Refs

struct TaskUserRef: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let avatarUrl: String?
}

struct TaskClientRef: Decodable, Sendable, Hashable { let id: String; let name: String; let slug: String }
struct TaskBlockRef: Decodable, Sendable, Hashable { let id: String; let name: String }

// MARK: - Task

struct TaskItem: Decodable, Sendable, Identifiable {
    let id: String
    let client: TaskClientRef?
    let assignees: [TaskUserRef]
    let createdBy: TaskUserRef?
    let featureBlock: TaskBlockRef?
    let parentId: String?
    let title: String
    let description: String?
    let acceptanceCriteria: String?
    let status: TaskStatus
    let priority: TaskPriority
    let orderKey: Double
    let dueDate: Date?
    let startedAt: Date?
    let completedAt: Date?
    let commentCount: Int
    let subtaskCount: Int
    let subtaskDoneCount: Int
    let createdAt: Date
    let updatedAt: Date
}

struct TaskComment: Decodable, Sendable, Identifiable {
    let id: String
    let author: TaskUserRef?
    let body: String
    let createdAt: Date
}

/// `GET /api/tasks/[id]` — the task plus its comments and one level of subtasks.
struct TaskItemDetail: Decodable, Sendable, Identifiable {
    let id: String
    let client: TaskClientRef?
    let assignees: [TaskUserRef]
    let createdBy: TaskUserRef?
    let featureBlock: TaskBlockRef?
    let parentId: String?
    let title: String
    let description: String?
    let acceptanceCriteria: String?
    let status: TaskStatus
    let priority: TaskPriority
    let orderKey: Double
    let dueDate: Date?
    let startedAt: Date?
    let completedAt: Date?
    let commentCount: Int
    let subtaskCount: Int
    let subtaskDoneCount: Int
    let createdAt: Date
    let updatedAt: Date
    let comments: [TaskComment]
    let subtasks: [TaskItem]
}

// MARK: - Feature blocks + milestones

struct FeatureBlock: Decodable, Sendable, Identifiable {
    let id: String
    let clientId: String
    let name: String
    let description: String?
    let startDate: Date?
    let endDate: Date?
    let orderKey: Double
    let color: String?
    let taskCount: Int
    let doneCount: Int
    let progress: Int
}

struct Milestone: Decodable, Sendable, Identifiable {
    let id: String
    let clientId: String
    let name: String
    let date: Date
    let description: String?
    let color: String?
}

// MARK: - Inputs

struct TaskInput: Encodable, Sendable {
    var clientId: String
    var title: String
    var description: String? = nil
    var acceptanceCriteria: String? = nil
    var status: TaskStatus? = nil
    var priority: TaskPriority? = nil
    var assigneeIds: [String]? = nil
    var featureBlockId: String? = nil
    var parentId: String? = nil
    var dueDate: String? = nil

    enum CodingKeys: String, CodingKey {
        case clientId, title, description, acceptanceCriteria, status, priority, assigneeIds, featureBlockId, parentId, dueDate
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clientId, forKey: .clientId)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(acceptanceCriteria, forKey: .acceptanceCriteria)
        try c.encodeIfPresent(status?.rawValue, forKey: .status)
        try c.encodeIfPresent(priority?.rawValue, forKey: .priority)
        try c.encodeIfPresent(assigneeIds, forKey: .assigneeIds)
        try c.encodeIfPresent(featureBlockId, forKey: .featureBlockId)
        try c.encodeIfPresent(parentId, forKey: .parentId)
        try c.encodeIfPresent(dueDate, forKey: .dueDate)
    }
}

/// Partial update — only the fields you set are sent (nil = leave unchanged).
struct TaskUpdate: Encodable, Sendable {
    var title: String? = nil
    var description: String? = nil
    var acceptanceCriteria: String? = nil
    var status: TaskStatus? = nil
    var priority: TaskPriority? = nil
    var assigneeIds: [String]? = nil
    var featureBlockId: String? = nil
    var dueDate: String? = nil

    enum CodingKeys: String, CodingKey {
        case title, description, acceptanceCriteria, status, priority, assigneeIds, featureBlockId, dueDate
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(acceptanceCriteria, forKey: .acceptanceCriteria)
        try c.encodeIfPresent(status?.rawValue, forKey: .status)
        try c.encodeIfPresent(priority?.rawValue, forKey: .priority)
        try c.encodeIfPresent(assigneeIds, forKey: .assigneeIds)
        try c.encodeIfPresent(featureBlockId, forKey: .featureBlockId)
        try c.encodeIfPresent(dueDate, forKey: .dueDate)
    }
}

struct FeatureBlockInput: Encodable, Sendable {
    var clientId: String
    var name: String
    var description: String? = nil
    var startDate: String? = nil
    var endDate: String? = nil
    var color: String? = nil

    enum CodingKeys: String, CodingKey { case clientId, name, description, startDate, endDate, color }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clientId, forKey: .clientId)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(startDate, forKey: .startDate)
        try c.encodeIfPresent(endDate, forKey: .endDate)
        try c.encodeIfPresent(color, forKey: .color)
    }
}

struct MilestoneInput: Encodable, Sendable {
    var clientId: String
    var name: String
    var date: String
    var description: String? = nil
    var color: String? = nil
}

// MARK: - Meetings (Scribe)

enum MeetingNoteStatus: String, Decodable, Sendable {
    case awaitingTranscript = "AWAITING_TRANSCRIPT"
    case transcribed = "TRANSCRIBED"
    case summarised = "SUMMARISED"
    case noTranscript = "NO_TRANSCRIPT"
    case error = "ERROR"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MeetingNoteStatus(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .awaitingTranscript: return "Awaiting notes"
        case .transcribed: return "Transcribed"
        case .summarised: return "Summarised"
        case .noTranscript: return "No notes"
        case .error: return "Error"
        case .unknown: return "—"
        }
    }
}

struct MeetingActionItem: Decodable, Sendable, Identifiable {
    let id: String
    let text: String
    let owner: String?
    let done: Bool
}

struct Meeting: Decodable, Sendable, Identifiable {
    let id: String
    let clientId: String
    let title: String
    let startedAt: Date?
    let endedAt: Date?
    let attendees: [String]
    let status: MeetingNoteStatus
    let summary: String?
    let decisions: [String]
    let transcriptText: String?
    let actionItems: [MeetingActionItem]
}

struct MeetingCandidate: Decodable, Sendable, Identifiable {
    let calendarEventId: String
    let title: String
    let start: Date
    let end: Date
    let meetingCode: String?
    let attendees: [String]
    let organizerEmail: String?

    var id: String { calendarEventId }
}

struct MeetingsResponse: Decodable, Sendable {
    let meetings: [Meeting]
    let candidates: [MeetingCandidate]
    let calendarConnected: Bool
}

struct MeetingResponse: Decodable, Sendable { let meeting: Meeting }

struct MeetingIngestInput: Encodable, Sendable {
    var calendarEventId: String
    var meetingCode: String
    var title: String
    var start: String? = nil
    var end: String? = nil
    var attendees: [String]? = nil

    enum CodingKeys: String, CodingKey { case calendarEventId, meetingCode, title, start, end, attendees }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(calendarEventId, forKey: .calendarEventId)
        try c.encode(meetingCode, forKey: .meetingCode)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(start, forKey: .start)
        try c.encodeIfPresent(end, forKey: .end)
        try c.encodeIfPresent(attendees, forKey: .attendees)
    }
}

// MARK: - Team members (assignee picker)

struct WorkspaceMember: Decodable, Sendable, Identifiable {
    let id: String
    let userId: String
    let role: String
    let user: UserRef

    struct UserRef: Decodable, Sendable {
        let id: String
        let name: String?
        let email: String
    }

    var displayName: String { user.name?.nilIfEmpty ?? user.email }
}
