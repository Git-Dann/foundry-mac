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

    @MainActor
    func testCallbackTokenParsedFromFragmentAndQuery() {
        let fragment = URL(string: "foundry://auth-callback#token=abc123")!
        XCTAssertEqual(WebAuthCoordinator.value(named: "token", in: fragment), "abc123")

        let query = URL(string: "foundry://auth-callback?token=xyz789")!
        XCTAssertEqual(WebAuthCoordinator.value(named: "token", in: query), "xyz789")

        let errorURL = URL(string: "foundry://auth-callback#error=domain")!
        XCTAssertEqual(WebAuthCoordinator.value(named: "error", in: errorURL), "domain")
        XCTAssertNil(WebAuthCoordinator.value(named: "token", in: errorURL))
    }

    func testWebDestinationResolvesAgainstBase() {
        let base = URL(string: "https://foundry.gitwork.co.uk")!
        XCTAssertEqual(
            WebDestination(path: "app/docs/123", title: "Doc").resolvedURL(base: base).absoluteString,
            "https://foundry.gitwork.co.uk/app/docs/123"
        )
        XCTAssertEqual(WebDestination(path: nil, title: "Home").resolvedURL(base: base), base)
    }
}
