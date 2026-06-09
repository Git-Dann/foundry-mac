import Foundation
import Observation

/// Owns the per-user authentication state: the Foundry mobile JWT (in the Keychain) and the
/// decoded current user. Sign-in is delegated to `WebAuthCoordinator` (ASWebAuthenticationSession).
@MainActor
@Observable
final class AuthStore {
    static let tokenKey = "auth.mobileJWT"

    private let keychain: KeychainStoring
    private let webAuth: WebAuthCoordinator

    private(set) var token: String?
    private(set) var currentUser: FoundryUser?
    private(set) var isAuthenticating = false
    var lastError: String?

    var isSignedIn: Bool { token != nil }

    init(keychain: KeychainStoring = KeychainStore(), webAuth: WebAuthCoordinator? = nil) {
        self.keychain = keychain
        // Created here (in the main-actor init) rather than as a default argument, since
        // WebAuthCoordinator's initializer is main-actor-isolated.
        self.webAuth = webAuth ?? WebAuthCoordinator()
        // Restore an existing session on launch.
        if let stored = (try? keychain.get(Self.tokenKey)) ?? nil, !stored.isEmpty {
            token = stored
            currentUser = FoundryUser(jwt: stored)
        }
    }

    /// Present the system sign-in sheet and persist the resulting JWT.
    func signIn(baseURL: URL) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        lastError = nil
        defer { isAuthenticating = false }

        do {
            let startURL = baseURL.appendingPathComponent("api/auth/desktop/start")
            let jwt = try await webAuth.authenticate(startURL: startURL)
            try keychain.set(jwt, for: Self.tokenKey)
            token = jwt
            currentUser = FoundryUser(jwt: jwt)
        } catch AppError.cancelled {
            // User dismissed the sheet — no error to show.
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
