import Foundation
import Observation

/// Single source of truth for environment-level config (API base URL, build info).
///
/// The production base URL lives here in ONE place. A debug override (Settings → API)
/// is read from `UserDefaults` so local development can point at a preview deployment
/// without shipping a second build. No secrets are ever stored here.
@Observable
final class AppEnvironment {
    /// Canonical production API base URL.
    ///
    /// Note: the iOS app historically used the `foundry-by-gitwork.vercel.app` alias;
    /// the canonical Gitwork-branded host is `foundry.gitwork.co.uk` (both resolve to the
    /// same deployment). The `/api-docs` page's `foundry.gitwork.co` is a documentation typo.
    static let productionBaseURL = URL(string: "https://foundry.gitwork.co.uk")!

    static let baseURLOverrideKey = "api.baseURLOverride"

    /// The effective API base URL (production unless a non-empty debug override is set).
    private(set) var baseURL: URL

    init(userDefaults: UserDefaults = .standard) {
        if let override = userDefaults.string(forKey: AppEnvironment.baseURLOverrideKey),
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = URL(string: override) {
            baseURL = url
        } else {
            baseURL = AppEnvironment.productionBaseURL
        }
    }

    /// Apply (or clear) the debug base-URL override and persist it.
    func setBaseURLOverride(_ string: String?, userDefaults: UserDefaults = .standard) {
        let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            userDefaults.removeObject(forKey: AppEnvironment.baseURLOverrideKey)
            baseURL = AppEnvironment.productionBaseURL
        } else if let url = URL(string: trimmed) {
            userDefaults.set(trimmed, forKey: AppEnvironment.baseURLOverrideKey)
            baseURL = url
        }
    }

    var isUsingProductionURL: Bool { baseURL == AppEnvironment.productionBaseURL }

    /// Marketing / hosted web app URL (same host) used by "Open Foundry Web".
    var webAppURL: URL { baseURL }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
