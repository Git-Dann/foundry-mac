import Foundation

// MARK: - Per-document analytics (GET /api/documents/[id]/analytics)

struct DocumentAnalytics: Decodable, Sendable {
    let documentId: String
    let totalViews: Int
    let uniqueVisitors: Int
    let returningVisitors: Int
    let firstViewedAt: Date?
    let lastViewedAt: Date?
    let avgDurationMs: Double?
    let totalDwellMs: Double
    let status: DocumentStatus
    let isShared: Bool
    let acceptedAt: Date?
    let declinedAt: Date?
    let timeToFirstOpenMs: Double?
    let sections: [SectionStat]
    let devices: [KeyCount]
    let browsers: [KeyCount]
    let locations: [KeyCount]
    let recentVisits: [Visit]

    struct SectionStat: Decodable, Sendable, Identifiable {
        let sectionKey: String
        let sectionTitle: String?
        let totalDwellMs: Double
        let avgDwellMs: Double
        let viewers: Int
        let avgScrollPct: Double?
        let sharePct: Double
        var id: String { sectionKey }
        var title: String { sectionTitle ?? sectionKey }
    }

    struct KeyCount: Decodable, Sendable, Identifiable {
        let key: String
        let count: Int
        var id: String { key }
    }

    struct Visit: Decodable, Sendable, Identifiable {
        let id: String
        let createdAt: Date
        let durationMs: Double?
        let visitorLabel: String
        let device: String?
        let browser: String?
        let os: String?
        let country: String?
        let city: String?
        let sectionsViewed: Int

        var place: String? {
            [city, country].compactMap { $0?.nilIfEmpty }.first
        }
    }

    var converted: Bool { acceptedAt != nil }
}

struct DocumentAnalyticsResponse: Decodable, Sendable { let analytics: DocumentAnalytics }

// MARK: - Cross-document analytics (GET /api/documents/analytics)

struct DocsAnalyticsSummary: Decodable, Sendable {
    let totals: Totals
    let rates: Rates
    let byStatus: [StatusCount]
    let topDocuments: [TopDocument]
    let topSections: [TopSection]

    struct Totals: Decodable, Sendable {
        let documents: Int
        let shared: Int
        let viewed: Int
        let sent: Int
        let accepted: Int
        let declined: Int
    }

    struct Rates: Decodable, Sendable {
        let openRate: Double?
        let winRate: Double?
        let avgTimeToFirstOpenMs: Double?
    }

    struct StatusCount: Decodable, Sendable, Identifiable {
        let status: DocumentStatus
        let count: Int
        var id: String { status.rawValue }
    }

    struct TopDocument: Decodable, Sendable, Identifiable {
        let id: String
        let title: String
        let documentNumber: String?
        let clientName: String?
        let status: DocumentStatus
        let views: Int
        let lastViewedAt: Date?
    }

    struct TopSection: Decodable, Sendable, Identifiable {
        let sectionKey: String
        let totalDwellMs: Double
        let avgDwellMs: Double
        let samples: Int
        var id: String { sectionKey }
    }
}

struct DocsAnalyticsResponse: Decodable, Sendable { let analytics: DocsAnalyticsSummary }

// MARK: - Versions (GET /api/documents/[id]/versions)

struct DocumentVersion: Decodable, Sendable, Identifiable {
    let id: String
    let version: String
    let changelog: String?
    let createdAt: Date
}

struct DocumentVersionsResponse: Decodable, Sendable { let versions: [DocumentVersion] }

// MARK: - Comments (GET /api/documents/[id]/comments)

struct DocumentComment: Decodable, Sendable, Identifiable {
    let id: String
    let authorName: String
    let authorKind: String
    let body: String
    let status: String
    let createdAt: Date
    let replies: [DocumentComment]?

    var isResolved: Bool { status == "RESOLVED" }
    var isFromClient: Bool { authorKind == "CLIENT" }
}

struct DocumentCommentsResponse: Decodable, Sendable { let comments: [DocumentComment] }
