import SwiftUI
import AppKit
import Observation

/// Root application model. Owns the long-lived stores and the cross-cutting UI state
/// (sidebar selection, menu→view command tokens). Injected into the SwiftUI environment.
@MainActor
@Observable
final class AppModel {
    let environment: AppEnvironment
    let auth: AuthStore
    let api: FoundryAPIClient
    let network: NetworkMonitor

    var selection: SidebarItem? = .dashboard
    var lastRefresh: Date?

    // Menu / toolbar actions are delivered to the focused feature view by bumping a token
    // the view observes via `.onChange`. Keeps menus decoupled from feature internals.
    private(set) var refreshToken = 0
    private(set) var newProposalToken = 0
    private(set) var searchToken = 0

    init() {
        let environment = AppEnvironment()
        let auth = AuthStore()
        self.environment = environment
        self.auth = auth
        self.api = FoundryAPIClient(environment: environment, auth: auth)
        self.network = NetworkMonitor()
    }

    func requestRefresh() {
        refreshToken &+= 1
        lastRefresh = Date()
    }

    func requestNewProposal() {
        selection = .proposals
        newProposalToken &+= 1
    }

    func requestSearch() {
        searchToken &+= 1
    }

    func signIn() {
        Task { await auth.signIn(baseURL: environment.baseURL) }
    }

    /// Open the hosted Foundry web app (⌘L) or a specific hosted path in the default browser.
    func openWeb(path: String? = nil) {
        var url = environment.webAppURL
        if let path {
            for segment in path.split(separator: "/") { url.appendPathComponent(String(segment)) }
        }
        NSWorkspace.shared.open(url)
    }
}
