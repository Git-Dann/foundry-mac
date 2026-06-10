import XCTest
@testable import Foundry

final class AppEnvironmentTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testDefaultsToProductionBaseURL() {
        let env = AppEnvironment(userDefaults: freshDefaults())
        XCTAssertEqual(env.baseURL, AppEnvironment.productionBaseURL)
        XCTAssertEqual(env.baseURL.absoluteString, "https://foundry.gitwork.co.uk")
        XCTAssertTrue(env.isUsingProductionURL)
    }

    func testBaseURLOverrideAppliesAndClears() {
        let defaults = freshDefaults()
        let env = AppEnvironment(userDefaults: defaults)

        env.setBaseURLOverride("https://foundry-preview.vercel.app", userDefaults: defaults)
        XCTAssertEqual(env.baseURL.absoluteString, "https://foundry-preview.vercel.app")
        XCTAssertFalse(env.isUsingProductionURL)

        env.setBaseURLOverride("", userDefaults: defaults)
        XCTAssertEqual(env.baseURL, AppEnvironment.productionBaseURL)
        XCTAssertTrue(env.isUsingProductionURL)
    }

    func testBaseURLOverrideRejectsForeignHosts() {
        let defaults = freshDefaults()
        let env = AppEnvironment(userDefaults: defaults)

        // The override carries the user's Bearer JWT on every call — foreign hosts must be ignored.
        env.setBaseURLOverride("https://evil.example.com", userDefaults: defaults)
        XCTAssertEqual(env.baseURL, AppEnvironment.productionBaseURL)
        // Plain HTTP to a remote host is also rejected (only localhost may use http).
        env.setBaseURLOverride("http://foundry.gitwork.co.uk", userDefaults: defaults)
        XCTAssertEqual(env.baseURL, AppEnvironment.productionBaseURL)
        // Local dev stays allowed.
        env.setBaseURLOverride("http://localhost:3000", userDefaults: defaults)
        XCTAssertEqual(env.baseURL.absoluteString, "http://localhost:3000")
        // A stored foreign override is ignored on launch too.
        defaults.set("https://evil.example.com", forKey: AppEnvironment.baseURLOverrideKey)
        XCTAssertEqual(AppEnvironment(userDefaults: defaults).baseURL, AppEnvironment.productionBaseURL)
    }
}
