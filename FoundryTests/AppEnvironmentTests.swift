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

        env.setBaseURLOverride("https://preview.example.com", userDefaults: defaults)
        XCTAssertEqual(env.baseURL.absoluteString, "https://preview.example.com")
        XCTAssertFalse(env.isUsingProductionURL)

        env.setBaseURLOverride("", userDefaults: defaults)
        XCTAssertEqual(env.baseURL, AppEnvironment.productionBaseURL)
        XCTAssertTrue(env.isUsingProductionURL)
    }
}
