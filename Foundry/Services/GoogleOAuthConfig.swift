import Foundation

/// Google "Desktop app" OAuth client config. PKCE flow — **no client secret is shipped or stored**.
/// The client ID is pasted in-app (Calendar → setup) and persisted in `UserDefaults`, so no
/// recompile is needed. A build-time default can also be dropped into `defaultClientID`.
enum GoogleOAuthConfig {
    static let clientIDKey = "google.oauth.clientID"

    /// Optional build-time default. Leave empty — paste the client ID in the Calendar window instead.
    static let defaultClientID = ""

    static var clientID: String {
        if let stored = UserDefaults.standard.string(forKey: clientIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty {
            return stored
        }
        return defaultClientID
    }

    static func setClientID(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: clientIDKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: clientIDKey)
        }
    }

    /// Optional. Google "Desktop app" clients issue a secret and the token endpoint usually wants
    /// it even with PKCE. It's the user's own installed-app secret (non-confidential per Google),
    /// pasted in-app and stored only in UserDefaults — never shipped in the repo.
    static let clientSecretKey = "google.oauth.clientSecret"

    static var clientSecret: String? {
        guard let raw = UserDefaults.standard.string(forKey: clientSecretKey) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func setClientSecret(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: clientSecretKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: clientSecretKey)
        }
    }

    static var isConfigured: Bool { !clientID.isEmpty }

    static let scopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/calendar.events",
    ]
    static let hostedDomain = "gitwork.co.uk"
    static let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    static let tokenEndpoint = "https://oauth2.googleapis.com/token"
}

/// Persisted Google session (Keychain). Encoded with a plain JSONEncoder so `Date` round-trips.
struct GoogleSession: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var email: String

    /// Treat as expired 60s early to avoid edge-of-expiry 401s.
    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}
