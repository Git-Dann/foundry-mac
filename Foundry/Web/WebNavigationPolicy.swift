import Foundation

/// Allow-list policy for the in-app WebKit bridge. Only Foundry's own origin (and the Google
/// sign-in domains needed to authenticate the hosted session) load in-app; everything else is
/// kicked out to the system browser. No JavaScript bridge is exposed.
enum WebNavigationPolicy {
    /// Domains permitted to load inside the WebView (matched as exact host or subdomain).
    static func allowedSuffixes(base: URL) -> [String] {
        var suffixes: [String] = []
        if let host = base.host?.lowercased() { suffixes.append(host) }
        // Google sign-in / asset domains so the hosted login flow can complete in-app.
        suffixes += [
            "google.com",
            "googleusercontent.com",
            "gstatic.com",
            "googleapis.com",
        ]
        return suffixes
    }

    static func isAllowed(_ url: URL, base: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let host = url.host?.lowercased() else { return false }
        return allowedSuffixes(base: base).contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
