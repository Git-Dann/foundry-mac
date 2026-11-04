import Foundation
import Observation

/// An edit waiting to reach the server. Kept on disk, so an edit made offline (or just before
/// quitting) is sent the next time the app can reach Foundry.
enum PendingOperation: Codable, Equatable, Sendable {
    case create(localId: String, NewCommitment)
    case update(id: String, CommitmentPatch)
    case delete(id: String)

    var targetId: String {
        switch self {
        case .create(let id, _), .update(let id, _), .delete(let id): id
        }
    }
}

/// What is written to disk: the last list the server gave us, plus edits not yet sent.
struct CommitmentCacheFile: Codable, Sendable {
    var userId: String
    var items: [Commitment]
    var settings: CommitmentSettings
    var loadedAt: Date?
    var outbox: [PendingOperation]
}

/// Reads and writes the cache file. One file per signed-in person; removed on sign-out.
struct CommitmentCache: Sendable {
    let directory: URL

    static let standard: CommitmentCache = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return CommitmentCache(directory: base.appending(path: "co.gitwork.foundry", directoryHint: .isDirectory))
    }()

    private func url(for userId: String) -> URL {
        let safe = userId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return directory.appending(path: "commitments-\(safe.isEmpty ? "user" : safe).json")
    }

    func load(userId: String) -> CommitmentCacheFile? {
        guard let data = try? Data(contentsOf: url(for: userId)),
              let file = try? JSONDecoder.foundry.decode(CommitmentCacheFile.self, from: data),
              file.userId == userId
        else { return nil }
        return file
    }

    func save(_ file: CommitmentCacheFile) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder.foundry.encode(file)
            try data.write(to: url(for: file.userId), options: [.atomic, .completeFileProtection])
        } catch {
            // The cache is a convenience; a failed write must never block an edit.
        }
    }

    func remove(userId: String) {
        try? FileManager.default.removeItem(at: url(for: userId))
    }
}

/// The one source of truth for commitments in the app (menu bar, window, intents, widget feed).
///
/// Every edit is applied locally first, so the UI never waits on the network, then queued and
/// sent in order. A failed send because we're offline keeps the queue; a send the server
/// refuses is dropped and reported, and the next refresh shows the server's version.
@MainActor
@Observable
final class CommitmentStore {
    private(set) var items: [Commitment] = []
    private(set) var settings: CommitmentSettings = .empty
    private(set) var loadedAt: Date?
    private(set) var isRefreshing = false
    private(set) var isCheckingSources = false
    private(set) var isOffline = false
    /// One plain sentence when something went wrong; cleared by the next success.
    var lastError: String?
    var lastCheckSummary: String?

    private(set) var outbox: [PendingOperation] = []
    var pendingCount: Int { outbox.count }

    /// Board tasks assigned to you, as last read. Kept apart so a failed board read leaves the
    /// last good list in place rather than emptying it.
    @ObservationIgnored private var boardItems: [Commitment] = []
    /// Set when the board couldn't be read; your own to-dos still show.
    private(set) var boardProblem: String?

    @ObservationIgnored private var service: CommitmentsService
    @ObservationIgnored private let cache: CommitmentCache
    @ObservationIgnored private var userId: String?
    @ObservationIgnored private var flushing = false
    @ObservationIgnored private var lastAutoCheck: Date?
    @ObservationIgnored var onChange: (([Commitment]) -> Void)?
    @ObservationIgnored var onUnauthorized: (() -> Void)?
    @ObservationIgnored var now: () -> Date = Date.init

    init(service: CommitmentsService, cache: CommitmentCache = .standard) {
        self.service = service
        self.cache = cache
    }

    // MARK: Session

    /// Load this person's cached list straight away (so the menu bar opens with something), then
    /// let the caller refresh in the background.
    func activate(userId: String) {
        guard self.userId != userId else { return }
        self.userId = userId
        if let file = cache.load(userId: userId) {
            items = file.items
            settings = file.settings
            loadedAt = file.loadedAt
            outbox = file.outbox
        } else {
            items = []; settings = .empty; loadedAt = nil; outbox = []
        }
        notify()
    }

    /// Signing out removes the cache: commitments are private, and the next person on this Mac
    /// must not see them.
    func deactivate() {
        if let userId { cache.remove(userId: userId) }
        userId = nil
        items = []; settings = .empty; loadedAt = nil; outbox = []; lastError = nil
        notify()
    }

    /// Switching servers: forget what's in memory but keep that person's cache on disk.
    func deactivateKeepingCache() {
        userId = nil
        items = []; settings = .empty; loadedAt = nil; outbox = []; lastError = nil
        notify()
    }

    var isStale: Bool {
        guard let loadedAt else { return true }
        return now().timeIntervalSince(loadedAt) > 60
    }

    // MARK: Reading

    func refresh() async {
        guard userId != nil, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        // Send queued edits first, so the list we fetch already includes them.
        await flush()
        do {
            try await load()
            // Read the person's sources when they're stale, so suggestions arrive without
            // anyone pressing Check now. The server only reads them by itself for people with
            // sent email or Slack switched on.
            if Self.sourcesAreDue(settings: settings, lastAutoCheck: lastAutoCheck, now: now()) {
                lastAutoCheck = now()
                isCheckingSources = true
                defer { isCheckingSources = false }
                _ = try await service.sync()
                try await load()
            }
        } catch {
            handle(error, context: "Couldn't reach Foundry")
        }
    }

    private func load() async throws {
        let response = try await service.list()
        isOffline = false
        settings = response.settings
        loadedAt = now()
        await loadBoard()
        if settings.gmailEnabled || settings.slackEnabled {
            // The AI read of email and Slack is retired in this app (it cost credit for things
            // Foundry already collects). Switch it off so the server stops trying too.
            var off = settings
            off.gmailEnabled = false
            off.slackEnabled = false
            if let saved = try? await service.updateSettings(off) { settings = saved } else { settings = off }
        }
        items = Self.reconcile(server: response.commitments + boardItems, outbox: outbox, now: now())
        if lastError?.hasPrefix("Couldn't reach") == true { lastError = nil }
        persistAndNotify()
    }

    private func loadBoard() async {
        guard let userId, !userId.isEmpty else { return }
        do {
            let tasks = try await service.boardTasks(assigneeId: userId)
            let at = now()
            boardItems = tasks.filter { BoardTasks.isRelevant($0, for: userId, now: at) }
                .map { BoardTasks.commitment($0, webPath: BoardTasks.path) }
            boardProblem = nil
        } catch let error as AppError where error.isUnauthorized {
            onUnauthorized?()
        } catch {
            if boardItems.isEmpty { boardItems = items.filter(\.isBoardTask) }
            boardProblem = "Your Foundry board tasks couldn't be read just now."
        }
    }

    /// When the last read is over this old, opening or refreshing the app reads the sources.
    static let autoCheckInterval: TimeInterval = 30 * 60

    /// Due when a source is on, the server isn't already reading, the last read is stale, and
    /// this app hasn't tried in the last half hour. The last rule matters: a read where one
    /// source fails doesn't move `lastSyncedAt` on, and without it every refresh would retry.
    static func sourcesAreDue(settings: CommitmentSettings, lastAutoCheck: Date?, now: Date) -> Bool {
        let anyOn = settings.gmailEnabled || settings.slackEnabled || settings.meetingsEnabled || settings.calendarEnabled
        guard anyOn, !settings.syncing else { return false }
        if let last = settings.lastSyncedAt, now.timeIntervalSince(last) < autoCheckInterval { return false }
        if let tried = lastAutoCheck, now.timeIntervalSince(tried) < autoCheckInterval { return false }
        return true
    }

    /// The server's list with our not-yet-sent edits laid over it, so a refresh never makes an
    /// edit appear to undo itself while it is still queued.
    static func reconcile(server: [Commitment], outbox: [PendingOperation], now: Date) -> [Commitment] {
        var byId = Dictionary(server.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var order = server.map(\.id)
        for op in outbox {
            switch op {
            case .create(let localId, let new):
                if byId[localId] == nil { order.insert(localId, at: 0) }
                byId[localId] = Commitment.local(id: localId, new, now: now)
            case .update(let id, let patch):
                if let c = byId[id] { byId[id] = patch.applied(to: c, now: now) }
            case .delete(let id):
                byId[id] = nil
            }
        }
        return order.compactMap { byId[$0] }
    }

    func commitment(id: String) -> Commitment? { items.first { $0.id == id } }

    // MARK: Editing

    @discardableResult
    func add(_ new: NewCommitment) -> Commitment {
        let localId = Commitment.localPrefix + UUID().uuidString
        let item = Commitment.local(id: localId, new, now: now())
        items.insert(item, at: 0)
        enqueue(.create(localId: localId, new))
        return item
    }

    /// Quick add: "Send the deck to Acme fri" → due Friday.
    @discardableResult
    func add(text: String) -> Commitment? {
        let parsed = DueDateParser.parse(text, now: now())
        let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return add(NewCommitment(title: String(title.prefix(200)), dueAt: parsed.dueAt))
    }

    func update(_ id: String, _ patch: CommitmentPatch) {
        guard !patch.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index] = patch.applied(to: items[index], now: now())
        enqueue(.update(id: id, patch))
    }

    func complete(_ id: String) { update(id, CommitmentPatch(state: .done)) }
    func reopen(_ id: String) { update(id, CommitmentPatch(state: .open, snoozedUntil: .clear)) }
    func accept(_ id: String) { update(id, CommitmentPatch(state: .open)) }
    func dismiss(_ id: String) { update(id, CommitmentPatch(state: .dismissed)) }
    func snooze(_ id: String, until: Date) {
        // A board task's date belongs to the board; snoozing it would only hide it here.
        guard commitment(id: id)?.isBoardTask != true else { return }
        update(id, CommitmentPatch(snoozedUntil: .set(until)))
    }
    func unsnooze(_ id: String) { update(id, CommitmentPatch(snoozedUntil: .clear)) }

    /// Only ones the person typed in can be deleted; suggestions are dismissed so they aren't
    /// suggested again.
    func delete(_ id: String) {
        guard let c = commitment(id: id), c.source == .manual else { return }
        items.removeAll { $0.id == id }
        enqueue(.delete(id: id))
    }

    func updateSettings(_ new: CommitmentSettings) async {
        let previous = settings
        settings = new
        persistAndNotify()
        do {
            settings = try await service.updateSettings(new)
            persistAndNotify()
        } catch {
            settings = previous
            persistAndNotify()
            handle(error, context: "Couldn't save your sources")
        }
    }

    /// Ask Foundry to read the switched-on sources now.
    func checkSources() async {
        guard !isCheckingSources else { return }
        isCheckingSources = true
        defer { isCheckingSources = false }
        do {
            lastAutoCheck = now()
            let result = try await service.sync()
            lastCheckSummary = Self.summary(of: result)
            await refresh()
        } catch {
            handle(error, context: "Couldn't check your sources")
        }
    }

    static func summary(of r: CommitmentSyncResult) -> String {
        if r.status == "busy" { return "Already checking. The new suggestions will appear when it's done." }
        let found = r.added == 0 ? "Nothing new to review." : (r.added == 1 ? "1 new to review." : "\(r.added) new to review.")
        guard let problem = SourceProblem.summary(r.sources) else { return found }
        return found + " " + problem
    }

    // MARK: Queue

    /// Folds an edit into the queue. Two edits to one commitment become one request, and editing
    /// something still waiting to be created changes the create instead.
    private func enqueue(_ op: PendingOperation) {
        outbox = Self.coalesce(outbox, adding: op)
        persistAndNotify()
        Task { await flush() }
    }

    static func coalesce(_ queue: [PendingOperation], adding op: PendingOperation) -> [PendingOperation] {
        var queue = queue
        switch op {
        case .update(let id, let patch):
            if let i = queue.firstIndex(where: { if case .create(id, _) = $0 { true } else { false } }),
               case .create(_, var new) = queue[i], patch.state == nil || patch.state == .open, patch.snoozedUntil == nil {
                // An edit to a not-yet-created commitment rewrites the create.
                if let t = patch.title?.value { new.title = t }
                if let n = patch.notes { new.notes = n.value }
                if let d = patch.dueAt { new.dueAt = d.value }
                if let c = patch.counterpart { new.counterpart = c.value }
                queue[i] = .create(localId: id, new)
                return queue
            }
            if let i = queue.lastIndex(where: { if case .update(id, _) = $0 { true } else { false } }) {
                if case .update(_, let earlier) = queue[i] { queue[i] = .update(id: id, earlier.merged(with: patch)) }
                return queue
            }
            queue.append(op)
        case .delete(let id):
            let hadCreate = queue.contains { if case .create(id, _) = $0 { true } else { false } }
            queue.removeAll { $0.targetId == id }
            if !hadCreate { queue.append(op) }
        case .create:
            queue.append(op)
        }
        return queue
    }

    /// Sends queued edits in order. Stops at the first network failure (still offline) and
    /// keeps the rest for later.
    func flush() async {
        guard !flushing, userId != nil else { return }
        flushing = true
        defer { flushing = false }
        while let op = outbox.first {
            do {
                switch op {
                case .create(let localId, let new):
                    let saved = try await service.create(new)
                    replaceLocalId(localId, with: saved)
                case .update(let id, let patch):
                    guard !id.hasPrefix(Commitment.localPrefix) else { break }
                    let saved: Commitment
                    if let taskId = id.hasPrefix(Commitment.boardPrefix) ? String(id.dropFirst(Commitment.boardPrefix.count)) : nil {
                        let current = items.first { $0.id == id }
                        let status = patch.state.flatMap { BoardTasks.status(for: $0, previous: current?.boardStatus) }
                        let due: CommitmentPatch.Field<String>? = patch.dueAt.map {
                            if case .set(let d) = $0 { .set(BoardTasks.dueDate(d)) } else { .clear }
                        }
                        guard status != nil || due != nil else { break }
                        var task = BoardTasks.commitment(
                            try await service.updateBoardTask(id: taskId, status: status, dueDate: due),
                            webPath: BoardTasks.path
                        )
                        // Reopening must remember where it came from, not "DONE".
                        if task.boardStatus == "DONE", let prev = current?.boardStatus, prev != "DONE" { task.boardStatus = prev }
                        saved = task
                        if let b = boardItems.firstIndex(where: { $0.id == id }) { boardItems[b] = saved }
                    } else {
                        saved = try await service.update(id: id, patch)
                    }
                    // Keep later local edits if any were made while this was in flight.
                    if !outbox.dropFirst().contains(where: { $0.targetId == id }),
                       let i = items.firstIndex(where: { $0.id == id }) {
                        items[i] = saved
                    }
                case .delete(let id):
                    try await service.delete(id: id)
                }
                isOffline = false
                if !outbox.isEmpty, outbox[0] == op { outbox.removeFirst() } else { outbox.removeAll { $0 == op } }
                persistAndNotify()
            } catch let error as AppError {
                if case .network = error { isOffline = true; return }
                if error.isUnauthorized { handle(error, context: ""); return }
                // The server refused this edit (e.g. it was already dismissed elsewhere). Drop it
                // so it doesn't block the queue, and say so.
                outbox.removeAll { $0 == op }
                lastError = "Foundry didn't accept a change: \(error.localizedDescription)"
                persistAndNotify()
            } catch {
                isOffline = true
                return
            }
        }
    }

    private func replaceLocalId(_ localId: String, with saved: Commitment) {
        if let i = items.firstIndex(where: { $0.id == localId }) { items[i] = saved }
        outbox = outbox.map { op in
            switch op {
            case .update(localId, let p): .update(id: saved.id, p)
            case .delete(localId): .delete(id: saved.id)
            default: op
            }
        }
    }

    // MARK: Helpers

    private func handle(_ error: Error, context: String) {
        if let appError = error as? AppError {
            if appError.isUnauthorized { onUnauthorized?(); return }
            if case .http(404, _) = appError {
                lastError = "To-dos aren't on this Foundry server yet."
                return
            }
            if case .network = appError {
                isOffline = true
                lastError = "Couldn't reach Foundry. Showing what was saved; changes will be sent when you're back online."
                return
            }
        }
        lastError = context.isEmpty ? error.localizedDescription : "\(context): \(error.localizedDescription)"
    }

    private func persistAndNotify() {
        if let userId {
            cache.save(CommitmentCacheFile(userId: userId, items: items, settings: settings, loadedAt: loadedAt, outbox: outbox))
        }
        notify()
    }

    private func notify() { onChange?(items) }

    #if DEBUG
    /// Screenshots and previews only.
    func loadForPreview(_ items: [Commitment], settings: CommitmentSettings = .empty) {
        self.items = items
        self.settings = settings
        self.loadedAt = now()
    }
    #endif
}

extension Commitment {
    static func local(id: String, _ new: NewCommitment, now: Date) -> Commitment {
        Commitment(
            id: id, title: new.title, notes: new.notes, dueAt: new.dueAt, state: .open, source: .manual,
            counterpart: new.counterpart, quote: nil, evidenceLabel: nil, evidenceUrl: nil, evidenceAt: nil,
            reason: nil, snoozedUntil: nil, doneAt: nil, createdAt: now, updatedAt: now
        )
    }
}
