import Foundation

/// `GET /api/health` — the only unauthenticated endpoint; used by Settings → API to verify
/// connectivity and the configured base URL.
struct HealthStatus: Codable, Sendable, Equatable {
    let ok: Bool
    let service: String
    let version: String?
    let timestamp: Date?
}
