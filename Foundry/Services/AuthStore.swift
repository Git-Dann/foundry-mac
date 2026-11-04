import Foundation
import AppKit
import Observation

/// Owns the per-user authentication state: the Foundry mobile JWT (in the Keychain) and the
/// decoded current user.
///
/// Sign-in opens the Foundry web login in the user's **default browser** (`NSWorkspace.open`).
/// The web bridge mints the per-user JWT and redirects to `foundry://auth-callback`, which the
/// app receives via `.onOpenURL` → `handleCallback`. No in-app Safari sheet, no embedded secret.
@MainActor
@Observable
final class AuthStore {
    static let tokenKey = "auth.mobileJWT"

    /// One Keychain slot per server. Production keeps the original slot; any other host (a
    /// preview or local server) gets its own, so a 401 from one server can never sign you out
    /// of another.
    nonisolated static func tokenKey(for baseURL: URL) -> String {
        if baseURL == AppEnvironment.productionBaseURL { return tokenKey }
        let host = baseURL.host ?? "unknown"
        return tokenKey + "@" + host + (baseURL.port.map { ":\($0)" } ?? "")
    }

    private let keychain: KeychainStoring
    private var slot: String

    private(set) var token: String?
    private(set) var currentUser: FoundryUser?
    private(set) var isAuthenticating = false
    var lastError: String?

    var isSignedIn: Bool { token != nil }

    init(keychain: KeychainStoring = AuthStore.defaultKeychain(), baseURL: URL = AppEnvironment.productionBaseURL) {
        self.keychain = keychain
        self.slot = Self.tokenKey(for: baseURL)
        restore()
    }

    /// Restore the session saved for the current server.
    private func restore() {
        if let stored = (try? keychain.get(slot)) ?? nil, !stored.isEmpty {
            token = stored
            currentUser = FoundryUser(jwt: stored)
        } else {
            token = nil
            currentUser = nil
        }
    }

    /// The API base URL changed: use that server's sign-in (if any), leaving the others alone.
    func switchServer(to baseURL: URL) {
        let next = Self.tokenKey(for: baseURL)
        guard next != slot else { return }
        slot = next
        lastError = nil
        restore()
    }

    /// Debug builds can use a separate Keychain slot (`-debug.keychainService <name>`), so testing
    /// against a local server never replaces the real sign-in.
    nonisolated static func defaultKeychain() -> KeychainStoring {
        #if DEBUG
        if let service = UserDefaults.standard.string(forKey: "debug.keychainService"), !service.isEmpty {
            return KeychainStore(service: service)
        }
        #endif
        return KeychainStore()
    }

    /// Open the Foundry web sign-in in the user's default browser.
    func signIn(baseURL: URL) {
        lastError = nil
        isAuthenticating = true
        NSWorkspace.shared.open(baseURL.appendingPathComponent("api/auth/desktop/start"))
    }

    /// Handle the `foundry://auth-callback` deep link (wired via `.onOpenURL`).
    func handleCallback(_ url: URL) {
        guard AuthCallback.isAuthCallback(url) else { return }
        isAuthenticating = false

        if let jwt = AuthCallback.token(from: url), !jwt.isEmpty {
            try? keychain.set(jwt, for: slot)
            token = jwt
            currentUser = FoundryUser(jwt: jwt)
            lastError = nil
        } else if let code = AuthCallback.errorCode(from: url) {
            lastError = code == "domain"
                ? AppError.unauthorizedDomain.errorDescription
                : "Sign-in failed (\(code))."
        } else {
            lastError = "Sign-in didn't return a token."
        }
    }

    func cancelSignIn() {
        isAuthenticating = false
    }

    func signOut() {
        try? keychain.remove(slot)
        token = nil
        currentUser = nil
        lastError = nil
    }

    /// Invoked by the API client when the server rejects the token (HTTP 401).
    func handleUnauthorized() {
        signOut()
        lastError = AppError.notAuthenticated.errorDescription
    }

    #if DEBUG
    /// Screenshots only: a signed-in look without touching the Keychain.
    func signInForPreview(email: String) {
        token = "preview"
        currentUser = FoundryUser(id: "preview", email: email, name: nil, role: "STAFF", permissions: [])
    }
    #endif
}
