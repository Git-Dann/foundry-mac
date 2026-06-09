import Foundation
import AppKit
import CryptoKit
import Security
import Observation

/// Per-user Google sign-in for Calendar, via the **PKCE desktop loopback flow** in the user's
/// DEFAULT browser (no GoogleSignIn SDK, no client secret shipped). Tokens live in the Keychain;
/// the access token is refreshed transparently. Separate from the Foundry platform JWT (`AuthStore`).
@MainActor
@Observable
final class GoogleAuthStore {
    static let sessionKey = "google.session"
    private let keychain: KeychainStoring

    private(set) var session: GoogleSession?
    private(set) var isAuthenticating = false
    var lastError: String?

    var isSignedIn: Bool { session != nil }
    var email: String? { session?.email }

    init(keychain: KeychainStoring = KeychainStore()) {
        self.keychain = keychain
        if let raw = (try? keychain.get(Self.sessionKey)) ?? nil,
           let data = raw.data(using: .utf8),
           let restored = try? JSONDecoder().decode(GoogleSession.self, from: data) {
            session = restored
        }
    }

    func signIn() async throws {
        guard GoogleOAuthConfig.isConfigured else {
            throw AppError.invalidConfiguration("Add your Google OAuth client ID first.")
        }
        lastError = nil
        isAuthenticating = true
        defer { isAuthenticating = false }

        let verifier = Self.codeVerifier()
        let challenge = Self.codeChallenge(verifier)
        let catcher = LoopbackCatcher()
        let port = try await catcher.start()
        defer { catcher.stop() }
        let redirectURI = "http://127.0.0.1:\(port)"

        var components = URLComponents(string: GoogleOAuthConfig.authEndpoint)!
        components.queryItems = [
            .init(name: "client_id", value: GoogleOAuthConfig.clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: GoogleOAuthConfig.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "hd", value: GoogleOAuthConfig.hostedDomain),
        ]
        guard let authURL = components.url else { throw AppError.invalidConfiguration("Couldn't build the sign-in URL.") }
        NSWorkspace.shared.open(authURL)

        let code = try await catcher.awaitCode()
        let newSession = try await Self.exchangeCode(code, verifier: verifier, redirectURI: redirectURI)
        guard newSession.email.lowercased().hasSuffix("@\(GoogleOAuthConfig.hostedDomain)") else {
            throw AppError.unauthorizedDomain
        }
        persist(newSession)
    }

    /// A non-expired access token, refreshing if necessary.
    func validAccessToken() async throws -> String {
        guard var current = session else { throw AppError.notAuthenticated }
        if !current.isExpired { return current.accessToken }
        let refreshed = try await Self.refresh(current)
        current.accessToken = refreshed.accessToken
        current.expiresAt = refreshed.expiresAt
        persist(current)
        return current.accessToken
    }

    func signOut() {
        try? keychain.remove(Self.sessionKey)
        session = nil
        lastError = nil
    }

    private func persist(_ session: GoogleSession) {
        self.session = session
        if let data = try? JSONEncoder().encode(session), let raw = String(data: data, encoding: .utf8) {
            try? keychain.set(raw, for: Self.sessionKey)
        }
    }

    // MARK: Token endpoints

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double?
        let refresh_token: String?
        let id_token: String?
    }

    private static func exchangeCode(_ code: String, verifier: String, redirectURI: String) async throws -> GoogleSession {
        let token = try await postToken([
            "client_id": GoogleOAuthConfig.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ])
        guard let refresh = token.refresh_token else {
            throw AppError.authenticationFailed("Google didn't return a refresh token. Try connecting again.")
        }
        let email = token.id_token.flatMap(emailFromIDToken) ?? ""
        return GoogleSession(
            accessToken: token.access_token,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(token.expires_in ?? 3600),
            email: email
        )
    }

    private static func refresh(_ session: GoogleSession) async throws -> (accessToken: String, expiresAt: Date) {
        let token = try await postToken([
            "client_id": GoogleOAuthConfig.clientID,
            "refresh_token": session.refreshToken,
            "grant_type": "refresh_token",
        ])
        return (token.access_token, Date().addingTimeInterval(token.expires_in ?? 3600))
    }

    private static func postToken(_ fields: [String: String]) async throws -> TokenResponse {
        guard let url = URL(string: GoogleOAuthConfig.tokenEndpoint) else { throw AppError.network("Bad token endpoint.") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields.map { "\($0.key)=\(formEncode($0.value))" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8).map { String($0.prefix(300)) } ?? ""
            throw AppError.authenticationFailed("Google token exchange failed. \(message)")
        }
        do { return try JSONDecoder().decode(TokenResponse.self, from: data) }
        catch { throw AppError.decoding("Couldn't read Google's token response.") }
    }

    // MARK: PKCE + helpers

    private static func codeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func codeChallenge(_ verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func emailFromIDToken(_ jwt: String) -> String? {
        let segments = jwt.split(separator: ".")
        guard segments.count == 3 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["email"] as? String
    }
}
