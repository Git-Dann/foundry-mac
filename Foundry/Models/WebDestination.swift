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

/// Hosted screens reached from the sidebar (modules not yet rebuilt natively) and the heavy
/// editors that intentionally stay in WebKit. All resolve against the configured base URL, so no
/// host is hard-coded. A single in-app login persists across these panes (shared persistent
/// `WKWebsiteDataStore`), so the user only signs in once.
extension WebDestination {
    // Whole modules embedded for now (native in a later phase).
    static let pulse = WebDestination(path: "app/pulse", title: "Pulse")
    static let care = WebDestination(path: "app/care", title: "Care")
    static let study = WebDestination(path: "app/study", title: "Study")
    static let backstage = WebDestination(path: "app/backstage", title: "Backstage")
    static let workspaceSettings = WebDestination(path: "app/settings", title: "Settings")

    // Heavy editors that stay in WebKit by design (opened contextually from native screens).
    static func docsEditor(id: String) -> WebDestination { .init(path: "app/docs/\(id)", title: "Edit Document") }
}
