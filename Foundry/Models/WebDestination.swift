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
