import SwiftUI
import AppKit
import Observation

/// Owns the long-lived pieces (sign-in, the commitment store, reachability, notifications,
/// widget feed, hotkey) and the little bit of UI state shared between the menu bar and window.
@MainActor
@Observable
final class AppModel {
    /// App Intents and the AppKit hotkey reach the running app through this.
    static let shared = AppModel()

    let environment: AppEnvironment
    let auth: AuthStore
    let store: CommitmentStore
    let network: NetworkMonitor
    let notifications: NotificationScheduler
    let calendar: CalendarStore
    let feed: FoundryFeedStore

    var selection: SidebarItem = .today
    var selectedCommitmentId: String?
    /// Bumped to move focus to the main window's quick-add field (⌘N).
    private(set) var focusQuickAddToken = 0
    private(set) var focusSearchToken = 0
    /// The last completion, for Undo.
    var lastCompleted: Commitment?

    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var wasOnline = true

    private init() {
        let environment = AppEnvironment()
        let auth = AuthStore(baseURL: environment.baseURL)
        self.environment = environment
        self.auth = auth
        self.network = NetworkMonitor()
        self.notifications = NotificationScheduler()
        self.store = CommitmentStore(service: CommitmentsAPI(
            baseURL: { await MainActor.run { environment.baseURL } },
            token: { await MainActor.run { auth.token } }
        ))
        self.calendar = CalendarStore(
            baseURL: { await MainActor.run { environment.baseURL } },
            token: { await MainActor.run { auth.token } }
        )
        self.feed = FoundryFeedStore(
            baseURL: { await MainActor.run { environment.baseURL } },
            token: { await MainActor.run { auth.token } }
        )
        // The sign-in token often carries no name; "dan@gitwork.co.uk" still says who "Dan" is.
        self.feed.myName = { [weak auth] in
            MainActor.assumeIsolated {
                guard let user = auth?.currentUser else { return nil }
                if let name = user.name, !name.isEmpty { return name }
                return user.email.split(separator: "@").first.map(String.init)
            }
        }

        Commitment.webBase = environment.baseURL
        store.onChange = { [weak self] items in self?.itemsChanged(items) }
        store.onUnauthorized = { [weak self] in self?.auth.handleUnauthorized(); self?.sessionChanged() }
        network.onChange = { [weak self] online in
            guard let self else { return }
            if online && !self.wasOnline { Task { await self.store.refresh() } }
            self.wasOnline = online
        }
        // As the unit-test host the app stays inert: no Keychain session, network or notifications.
        guard NSClassFromString("XCTestCase") == nil else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo") || ProcessInfo.processInfo.arguments.contains("--render-screenshots") {
            store.onChange = nil  // sample data must never reach real notifications or the widget
            auth.signInForPreview(email: "dan@gitwork.co.uk")
            let sample = SampleData.items(now: Date())
            store.loadForPreview(sample, settings: SampleData.settings)
            let week = CalendarLayout.days(around: Date(), mode: .week)
            calendar.loadForPreview(SampleData.events(week: week), from: week.first!, to: Calendar.current.date(byAdding: .day, value: 1, to: week.last!)!)
            selectedCommitmentId = sample.first { $0.source == .meeting && $0.state == .open }?.id
            return
        }
        #endif
        sessionChanged()
        startTimer()
    }

    // MARK: Session

    func sessionChanged() {
        if let user = auth.currentUser, auth.isSignedIn {
            store.activate(userId: user.id)
            Task { await store.refresh() }
            notifications.requestAuthorizationIfNeeded()
        } else {
            store.deactivate()
            calendar.clear()
            notifications.clearAll()
        }
    }

    /// Advanced → API base URL changed.
    func serverChanged() {
        Commitment.webBase = environment.baseURL
        auth.switchServer(to: environment.baseURL)
        store.deactivateKeepingCache()
        calendar.clear()
        sessionChanged()
    }

    func signOut() {
        auth.signOut()
        sessionChanged()
    }

    func handleURL(_ url: URL) {
        if AuthCallback.isAuthCallback(url) {
            auth.handleCallback(url)
            sessionChanged()
            return
        }
        // foundry://commitment/<id> (from the widget or a notification) opens it in the window.
        if url.scheme == "foundry", url.host == "commitment" {
            let id = url.lastPathComponent
            showInWindow(id: id.isEmpty ? nil : id)
        }
    }

    // MARK: Refresh

    /// Quiet background refresh: every 5 minutes while signed in. Opening the menu bar or window
    /// also refreshes when the list is over a minute old.
    private func startTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.auth.isSignedIn else { return }
                await self.store.refresh()
            }
        }
    }

    func refreshIfStale() {
        guard auth.isSignedIn, store.isStale else { return }
        Task { await store.refresh() }
    }

    private func itemsChanged(_ items: [Commitment]) {
        WidgetPublisher.publish(items, signedIn: auth.isSignedIn)
        notifications.reschedule(items: items)
    }

    // MARK: Actions shared by menu bar, window, notifications and intents

    func complete(_ id: String) {
        guard let c = store.commitment(id: id) else { return }
        store.complete(id)
        lastCompleted = c
    }

    func undoComplete() {
        guard let c = lastCompleted else { return }
        store.update(c.id, CommitmentPatch(state: c.state == .suggested ? .open : c.state, snoozedUntil: c.snoozedUntil.map { .set($0) } ?? .clear))
        lastCompleted = nil
    }

    func requestQuickAddFocus() { focusQuickAddToken &+= 1 }
    func requestSearchFocus() { focusSearchToken &+= 1 }

    func showInWindow(id: String?) {
        if let id, let c = store.commitment(id: id) {
            selection = c.state == .suggested ? .today : (c.state == .done ? .done : (sidebarItem(for: c)))
            selectedCommitmentId = id
        }
        openMainWindow()
    }

    private func sidebarItem(for c: Commitment) -> SidebarItem {
        let g = CommitmentGrouping.group(c, now: Date())
        return (g == .overdue || g == .today) ? .today : .upcoming
    }

    /// Opens (or brings forward) the main window. Set by the SwiftUI scene once it exists.
    @ObservationIgnored var openWindowAction: (() -> Void)?

    func openMainWindow() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindowAction?()
        }
    }

    func openFoundryWeb() {
        NSWorkspace.shared.open(environment.webAppURL.appending(path: "app/backstage").appending(queryItems: [URLQueryItem(name: "area", value: "commitments")]))
    }
}

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case today, upcoming, calendar, foundry, done
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .calendar: "Calendar"
        case .foundry: "Foundry"
        case .done: "Done"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .upcoming: "calendar.day.timeline.left"
        case .calendar: "calendar"
        case .foundry: "bubble.left.and.text.bubble.right"
        case .done: "checkmark.circle"
        }
    }
}
