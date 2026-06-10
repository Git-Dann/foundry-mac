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
           let url = URL(string: override),
           AppEnvironment.isAllowedOverride(url) {
            baseURL = url
        } else {
            baseURL = AppEnvironment.productionBaseURL
        }
    }

    /// The debug override may only point at Foundry's own hosts (production domain or a Vercel
    /// preview) or local dev. Every API call attaches the user's Bearer JWT, so an arbitrary
    /// host here would hand the session token to whoever runs that server.
    static func isAllowedOverride(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return false }
        if host == "localhost" || host == "127.0.0.1" {
            return scheme == "http" || scheme == "https"
        }
        guard scheme == "https" else { return false }
        let allowedSuffixes = ["gitwork.co.uk", "vercel.app"]
        return allowedSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Apply (or clear) the debug base-URL override and persist it. Disallowed hosts are ignored.
    func setBaseURLOverride(_ string: String?, userDefaults: UserDefaults = .standard) {
        let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            userDefaults.removeObject(forKey: AppEnvironment.baseURLOverrideKey)
            baseURL = AppEnvironment.productionBaseURL
        } else if let url = URL(string: trimmed), AppEnvironment.isAllowedOverride(url) {
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
