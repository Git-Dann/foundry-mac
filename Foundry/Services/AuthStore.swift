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

    private let keychain: KeychainStoring

    private(set) var token: String?
    private(set) var currentUser: FoundryUser?
    private(set) var isAuthenticating = false
    var lastError: String?

    var isSignedIn: Bool { token != nil }

    init(keychain: KeychainStoring = KeychainStore()) {
        self.keychain = keychain
        // Restore an existing session on launch.
        if let stored = (try? keychain.get(Self.tokenKey)) ?? nil, !stored.isEmpty {
            token = stored
            currentUser = FoundryUser(jwt: stored)
        }
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
            try? keychain.set(jwt, for: Self.tokenKey)
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
        try? keychain.remove(Self.tokenKey)
        token = nil
        currentUser = nil
        lastError = nil
    }

    /// Invoked by the API client when the server rejects the token (HTTP 401).
    func handleUnauthorized() {
        signOut()
        lastError = AppError.notAuthenticated.errorDescription
    }
}
