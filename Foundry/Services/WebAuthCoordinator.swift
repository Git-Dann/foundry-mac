import AuthenticationServices
import AppKit

/// Drives sign-in through Apple's `ASWebAuthenticationSession` — the system-blessed way to
/// authenticate a native app against a web service.
///
/// Flow: open `https://<base>/api/auth/desktop/start` in the system auth sheet. The user signs
/// in with their @gitwork.co.uk Google account on the real Foundry site; the server mints the
/// existing per-user mobile JWT and 302-redirects to `foundry://auth-callback#token=<jwt>`.
/// We capture that callback (registered URL scheme `foundry`) and return the token. No Google
/// SDK, no embedded secret.
@MainActor
final class WebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let callbackScheme = "foundry"

    /// Held strongly for the duration of the session (ASWebAuthenticationSession is otherwise
    /// not retained and would be torn down before completing).
    private var session: ASWebAuthenticationSession?

    func authenticate(startURL: URL) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let session = ASWebAuthenticationSession(
                url: startURL,
                callbackURLScheme: Self.callbackScheme
            ) { callbackURL, error in
                if let error {
                    let code = (error as? ASWebAuthenticationSessionError)?.code
                    if code == .canceledLogin {
                        continuation.resume(throwing: AppError.cancelled)
                    } else {
                        continuation.resume(throwing: AppError.authenticationFailed(error.localizedDescription))
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: AppError.authenticationFailed("Sign-in returned no callback."))
                    return
                }
                if let token = Self.value(named: "token", in: callbackURL) {
                    continuation.resume(returning: token)
                } else if let errorCode = Self.value(named: "error", in: callbackURL) {
                    if errorCode == "domain" {
                        continuation.resume(throwing: AppError.unauthorizedDomain)
                    } else {
                        continuation.resume(throwing: AppError.authenticationFailed(errorCode))
                    }
                } else {
                    continuation.resume(throwing: AppError.authenticationFailed("Sign-in did not return a token."))
                }
            }
            session.presentationContextProvider = self
            // Reuse the system's existing Google session for smoother SSO.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: AppError.authenticationFailed("Couldn't start the sign-in session."))
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        }
    }

    /// Reads a value from either the URL fragment (`#token=…`, preferred — kept out of logs/Referer)
    /// or the query string (`?token=…`).
    static func value(named name: String, in url: URL) -> String? {
        if let fragment = url.fragment, let v = parse(fragment, key: name) { return v }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let v = items.first(where: { $0.name == name })?.value {
            return v
        }
        return nil
    }

    private static func parse(_ encoded: String, key: String) -> String? {
        for pair in encoded.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2, kv[0] == key {
                return kv[1].removingPercentEncoding ?? kv[1]
            }
        }
        return nil
    }
}
