import Foundation

/// Unified error type for the app. Mirrors the iOS app's `AppError` (so behaviour matches
/// the proven client) with a couple of Mac-specific additions (`http`, `notAuthenticated`,
/// `cancelled`).
enum AppError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case authenticationFailed(String)
    case unauthorizedDomain
    case notAuthenticated
    case http(status: Int, message: String)
    case network(String)
    case decoding(String)
    case persistence(String)
    case unavailable(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): return message
        case .authenticationFailed(let message): return message
        case .unauthorizedDomain:
            return "Only @gitwork.co.uk Google accounts can sign in to Foundry."
        case .notAuthenticated:
            return "You're signed out. Sign in to Foundry to continue."
        case .http(let status, let message):
            return message.isEmpty ? "Request failed (HTTP \(status))." : message
        case .network(let message): return message
        case .decoding(let message): return message
        case .persistence(let message): return message
        case .unavailable(let message): return message
        case .cancelled: return "Cancelled."
        }
    }

    /// True for HTTP 401 — the API client maps this to a re-authentication prompt.
    var isUnauthorized: Bool {
        if case .http(let status, _) = self { return status == 401 }
        if case .notAuthenticated = self { return true }
        return false
    }
}
