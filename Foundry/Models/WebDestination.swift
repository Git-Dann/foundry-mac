import Foundation

/// A hosted Foundry screen to open in the in-app WebKit window. Carries a path (resolved
/// against the configured base URL) so the window never holds a hard-coded host.
struct WebDestination: Codable, Hashable, Identifiable {
    var path: String?
    var title: String

    var id: String { "\(path ?? "/")|\(title)" }

    func resolvedURL(base: URL) -> URL {
        guard let path, !path.isEmpty else { return base }
        var url = base
        for segment in path.split(separator: "/") { url.appendPathComponent(String(segment)) }
        return url
    }
}

// MARK: - Presets

/// Hosted screens that intentionally stay in WebKit. Everything else is native — heavy editors
/// (Docs section editor, Pulse full report, Care report builder) are opened contextually with an
/// inline `WebDestination`. All resolve against the configured base URL, so no host is
/// hard-coded; a single in-pane login persists (shared `WKWebsiteDataStore`).
extension WebDestination {
    /// Study — the multi-agent research runner stays embedded by design.
    static let study = WebDestination(path: "app/study", title: "Study")
}
