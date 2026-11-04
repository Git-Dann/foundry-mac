import XCTest
@testable import Foundry

final class AuthTests: XCTestCase {
    /// base64url-encode a JSON payload into the middle segment of a fake JWT.
    private func makeJWT(payload: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(b64).signature"
    }

    func testFoundryUserDecodesFromJWTClaims() throws {
        let jwt = try makeJWT(payload: [
            "sub": "user_123",
            "email": "dan@gitwork.co.uk",
            "role": "ADMIN",
            "permissions": ["docs.manage", "clients.manage"],
        ])
        let user = FoundryUser(jwt: jwt)
        XCTAssertNotNil(user)
        XCTAssertEqual(user?.id, "user_123")
        XCTAssertEqual(user?.email, "dan@gitwork.co.uk")
        XCTAssertEqual(user?.role, "ADMIN")
        XCTAssertEqual(user?.permissions, ["docs.manage", "clients.manage"])
        XCTAssertTrue(user?.can("anything") ?? false) // ADMIN can do anything
    }

    func testFoundryUserRejectsMalformedJWT() {
        XCTAssertNil(FoundryUser(jwt: "not-a-jwt"))
        XCTAssertNil(FoundryUser(jwt: "a.b")) // wrong segment count
    }

    func testCallbackTokenParsedFromFragmentAndQuery() {
        let fragment = URL(string: "foundry://auth-callback#token=abc123")!
        XCTAssertEqual(AuthCallback.value(named: "token", in: fragment), "abc123")

        let query = URL(string: "foundry://auth-callback?token=xyz789")!
        XCTAssertEqual(AuthCallback.value(named: "token", in: query), "xyz789")

        let errorURL = URL(string: "foundry://auth-callback#error=domain")!
        XCTAssertEqual(AuthCallback.value(named: "error", in: errorURL), "domain")
        XCTAssertNil(AuthCallback.value(named: "token", in: errorURL))
    }

    func testOnlyTheAuthCallbackHostCountsAsSignIn() {
        XCTAssertTrue(AuthCallback.isAuthCallback(URL(string: "foundry://auth-callback#token=a")!))
        XCTAssertFalse(AuthCallback.isAuthCallback(URL(string: "foundry://commitment/abc")!))
        XCTAssertFalse(AuthCallback.isAuthCallback(URL(string: "https://auth-callback")!))
    }

    func testEachServerHasItsOwnKeychainSlot() {
        XCTAssertEqual(AuthStore.tokenKey(for: AppEnvironment.productionBaseURL), "auth.mobileJWT", "Production keeps the existing slot")
        XCTAssertEqual(AuthStore.tokenKey(for: URL(string: "http://localhost:3100")!), "auth.mobileJWT@localhost:3100")
        XCTAssertNotEqual(AuthStore.tokenKey(for: URL(string: "https://preview.vercel.app")!), AuthStore.tokenKey(for: AppEnvironment.productionBaseURL))
    }

    @MainActor
    func testSigningOutOfOneServerLeavesAnotherSignedIn() {
        let keychain = MemoryKeychain()
        try? keychain.set("prod-token", for: AuthStore.tokenKey(for: AppEnvironment.productionBaseURL))
        let auth = AuthStore(keychain: keychain, baseURL: URL(string: "http://localhost:3100")!)
        XCTAssertFalse(auth.isSignedIn)
        auth.handleUnauthorized()
        auth.switchServer(to: AppEnvironment.productionBaseURL)
        XCTAssertEqual(auth.token, "prod-token")
    }
}

final class MemoryKeychain: KeychainStoring {
    var values: [String: String] = [:]
    func set(_ value: String, for key: String) throws { values[key] = value }
    func get(_ key: String) throws -> String? { values[key] }
    func remove(_ key: String) throws { values[key] = nil }
}
