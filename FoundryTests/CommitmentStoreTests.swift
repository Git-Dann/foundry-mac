import XCTest
@testable import Foundry

/// An in-memory server. `offline` makes every call fail the way URLSession does.
actor FakeService: CommitmentsService {
    var server: [String: Commitment] = [:]
    var offline = false
    var refuse = false
    var calls: [String] = []
    private var counter = 0

    func setOffline(_ v: Bool) { offline = v }
    func setRefuse(_ v: Bool) { refuse = v }
    var settings = CommitmentSettings.empty
    var syncAdvancesLastSynced = true
    func setSettings(_ s: CommitmentSettings) { settings = s }
    func setSyncAdvances(_ v: Bool) { syncAdvancesLastSynced = v }
    var syncCount: Int { calls.filter { $0 == "sync" }.count }
    func seed(_ c: Commitment) { server[c.id] = c }

    private func check(_ name: String) throws {
        calls.append(name)
        if offline { throw AppError.network("The Internet connection appears to be offline.") }
        if refuse { throw AppError.http(status: 400, message: "Nope") }
    }

    func list() async throws -> CommitmentsResponse {
        try check("list")
        return CommitmentsResponse(commitments: server.values.sorted { $0.createdAt > $1.createdAt }, settings: settings, lists: lists)
    }
    func create(_ new: NewCommitment) async throws -> Commitment {
        try check("create")
        counter += 1
        let c = Commitment.local(id: "srv\(counter)", new, now: Date())
        server[c.id] = c
        return c
    }
    func update(id: String, _ patch: CommitmentPatch) async throws -> Commitment {
        try check("update:\(id)")
        guard let c = server[id] else { throw AppError.http(status: 404, message: "Not found") }
        server[id] = patch.applied(to: c, now: Date())
        return server[id]!
    }
    func delete(id: String) async throws { try check("delete:\(id)"); server[id] = nil }
    func sync() async throws -> CommitmentSyncResult {
        try check("sync")
        if syncAdvancesLastSynced { settings.lastSyncedAt = Date() }
        return .init(status: syncAdvancesLastSynced ? "ok" : "partial", added: 0, sources: [:])
    }
    func updateSettings(_ s: CommitmentSettings) async throws -> CommitmentSettings { try check("settings"); return s }

    var lists: [TodoList] = []
    func createList(name: String, color: String?, symbol: String?, area: String?) async throws -> TodoList {
        try check("createList")
        let l = TodoList(id: "list\(lists.count + 1)", name: name, color: color, symbol: symbol, area: area, orderKey: Double(lists.count), archived: false)
        lists.append(l)
        return l
    }
    func updateList(_ list: TodoList) async throws -> TodoList { try check("updateList"); return list }
    func deleteList(id: String) async throws { try check("deleteList"); lists.removeAll { $0.id == id } }
    var reordered: [String] = []
    func reorder(ids: [String]) async throws { try check("reorder"); reordered = ids }

    var board: [String: BoardTaskDTO] = [:]
    var boardFails = false
    func seedBoard(_ t: BoardTaskDTO) { board[t.id] = t }
    func setBoardFails(_ v: Bool) { boardFails = v }
    func boardTasks(assigneeId: String) async throws -> [BoardTaskDTO] {
        calls.append("board:\(assigneeId)")
        if boardFails { throw AppError.http(status: 500, message: "Board down") }
        return Array(board.values)
    }
    func updateBoardTask(id: String, status: String?, dueDate: CommitmentPatch.Field<String>?) async throws -> BoardTaskDTO {
        calls.append("boardUpdate:\(id):\(status ?? "-"):\(dueDate.map { "\($0)" } ?? "-")")
        guard var t = board[id] else { throw AppError.http(status: 404, message: "Not found") }
        if let status { t.status = status; t.completedAt = status == "DONE" ? Date() : nil }
        if let dueDate { if case .set(let d) = dueDate { t.dueDate = d } else { t.dueDate = nil } }
        board[id] = t
        return t
    }
}

func boardTask(_ id: String, _ title: String, status: String = "DOING", due: String? = nil) -> BoardTaskDTO {
    BoardTaskDTO(
        id: id, assignees: [.init(id: "u1")], title: title, status: status, dueDate: due, completedAt: nil, archivedAt: nil, parentId: nil,
        client: .init(id: "c1", name: "Fellas", slug: "fellas"), createdAt: Date(), updatedAt: Date()
    )
}

@MainActor
final class CommitmentStoreTests: XCTestCase {
    var dir: URL!
    var cache: CommitmentCache { CommitmentCache(directory: dir) }

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: "store-\(UUID().uuidString)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func makeStore(_ service: FakeService) -> CommitmentStore {
        let s = CommitmentStore(service: service, cache: cache)
        s.activate(userId: "u1")
        return s
    }

    func testAddIsInstantThenGetsTheServerId() async {
        let service = FakeService()
        let store = makeStore(service)
        let local = store.add(text: "Send Acme the deck fri")
        XCTAssertEqual(store.items.first?.title, "Send Acme the deck")
        XCTAssertTrue(local!.isLocalOnly)
        await store.flush()
        XCTAssertEqual(store.items.first?.id, "srv1")
        XCTAssertTrue(store.outbox.isEmpty)
    }

    func testOfflineEditsQueueSurviveRelaunchAndSendInOrder() async {
        let service = FakeService()
        await service.seed(Commitment.local(id: "s1", NewCommitment(title: "Existing"), now: Date()))
        let store = makeStore(service)
        await store.refresh()
        await service.setOffline(true)

        store.complete("s1")
        let added = store.add(text: "Offline one")!
        store.update(added.id, CommitmentPatch(notes: .set("note")))
        await store.flush()
        XCTAssertTrue(store.isOffline)
        XCTAssertEqual(store.items.first { $0.id == "s1" }?.state, .done, "Applied locally straight away")
        XCTAssertEqual(store.outbox.count, 2, "Edit to the new one folds into its create")

        // Quit and relaunch while offline: the cache still holds the edits.
        let relaunched = CommitmentStore(service: service, cache: cache)
        relaunched.activate(userId: "u1")
        XCTAssertEqual(relaunched.outbox.count, 2)
        XCTAssertEqual(relaunched.items.first { $0.id == "s1" }?.state, .done)

        await service.setOffline(false)
        await relaunched.refresh()
        XCTAssertTrue(relaunched.outbox.isEmpty)
        let server = await service.server
        XCTAssertEqual(server["s1"]?.state, .done)
        XCTAssertEqual(server.values.first { $0.title == "Offline one" }?.notes, "note")
        XCTAssertFalse(relaunched.isOffline)
    }

    func testRefreshKeepsUnsentEditsVisible() async {
        let service = FakeService()
        await service.seed(Commitment.local(id: "s1", NewCommitment(title: "Existing"), now: Date()))
        let store = makeStore(service)
        await store.refresh()
        await service.setOffline(true)
        store.snooze("s1", until: Date().addingTimeInterval(3600))
        let merged = CommitmentStore.reconcile(server: await service.server.values.map { $0 }, outbox: store.outbox, now: Date())
        XCTAssertNotNil(merged.first?.snoozedUntil)
    }

    func testRefusedEditIsDroppedAndReported() async {
        let service = FakeService()
        await service.seed(Commitment.local(id: "s1", NewCommitment(title: "Existing"), now: Date()))
        let store = makeStore(service)
        await store.refresh()
        await service.setRefuse(true)
        store.dismiss("s1")
        await store.flush()
        XCTAssertTrue(store.outbox.isEmpty, "A refused edit can't block the queue")
        XCTAssertNotNil(store.lastError)
    }

    func testDeletingAnUnsentCommitmentSendsNothing() async {
        let service = FakeService()
        await service.setOffline(true)
        let store = makeStore(service)
        let c = store.add(text: "Never mind")!
        store.delete(c.id)
        XCTAssertTrue(store.outbox.isEmpty)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testSuggestionsCannotBeDeletedOnlyDismissed() async {
        let service = FakeService()
        var s = Commitment.local(id: "sg", NewCommitment(title: "Suggested"), now: Date())
        s.state = .suggested; s.source = .gmail
        await service.seed(s)
        let store = makeStore(service)
        await store.refresh()
        store.delete("sg")
        XCTAssertNotNil(store.commitment(id: "sg"))
    }

    func testSignOutRemovesTheCache() async {
        let service = FakeService()
        let store = makeStore(service)
        store.add(text: "Private")
        await store.flush()
        store.deactivate()
        XCTAssertNil(cache.load(userId: "u1"))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testTwoEditsBecomeOneRequest() {
        var q = CommitmentStore.coalesce([], adding: .update(id: "a", CommitmentPatch(state: .done)))
        q = CommitmentStore.coalesce(q, adding: .update(id: "a", CommitmentPatch(state: .open, snoozedUntil: .clear)))
        XCTAssertEqual(q, [.update(id: "a", CommitmentPatch(state: .open, snoozedUntil: .clear))])
    }

    func testOpeningReadsStaleSourcesOnce() async {
        let service = FakeService()
        let store = makeStore(service)
        await store.refresh()
        let first = await service.syncCount
        XCTAssertEqual(first, 1, "Never read: the first refresh reads the sources")
        XCTAssertNotNil(store.settings.lastSyncedAt)
        await store.refresh()
        let second = await service.syncCount
        XCTAssertEqual(second, 1, "Read just now: the next refresh doesn't read again")
    }

    func testAPartialReadDoesNotRetryOnEveryRefresh() async {
        let service = FakeService()
        await service.setSyncAdvances(false) // one source failed, so lastSyncedAt stays old
        let store = makeStore(service)
        for _ in 0..<4 { await store.refresh() }
        let count = await service.syncCount
        XCTAssertEqual(count, 1)
    }

    func testNothingIsReadWhenEverySourceIsOffOrAlreadyRunning() {
        var s = CommitmentSettings.empty
        s.meetingsEnabled = false; s.calendarEnabled = false
        XCTAssertFalse(CommitmentStore.sourcesAreDue(settings: s, lastAutoCheck: nil, now: Date()))
        var running = CommitmentSettings.empty
        running.syncing = true
        XCTAssertFalse(CommitmentStore.sourcesAreDue(settings: running, lastAutoCheck: nil, now: Date()))
        var stale = CommitmentSettings.empty
        stale.lastSyncedAt = Date().addingTimeInterval(-31 * 60)
        XCTAssertTrue(CommitmentStore.sourcesAreDue(settings: stale, lastAutoCheck: nil, now: Date()))
        stale.lastSyncedAt = Date().addingTimeInterval(-29 * 60)
        XCTAssertFalse(CommitmentStore.sourcesAreDue(settings: stale, lastAutoCheck: nil, now: Date()))
    }

    // MARK: Board tasks

    func testBoardTasksJoinYourOwnToDos() async {
        let fake = FakeService()
        await fake.seedBoard(boardTask("t1", "Fix login redirect", due: "2026-11-06"))
        await fake.seedBoard(boardTask("t2", "Someday idea", status: "BACKLOG"))
        await fake.seedBoard(boardTask("t3", "Planned", status: "BACKLOG", due: "2026-11-10T00:00:00.000Z"))
        var someoneElses = boardTask("t4", "Harry's task")
        someoneElses.assignees = [.init(id: "u2")]
        await fake.seedBoard(someoneElses)
        let store = CommitmentStore(service: fake, cache: cache)
        store.activate(userId: "u1")
        await store.refresh()
        let board = store.items.filter(\.isBoardTask)
        XCTAssertEqual(Set(board.map(\.title)), ["Fix login redirect", "Planned"], "no undated backlog, nobody else's tasks")
        XCTAssertEqual(board.first { $0.title == "Fix login redirect" }?.counterpart, "Fellas")
        let calls = await fake.calls
        XCTAssertTrue(calls.contains("board:u1"))
    }

    func testTickingABoardTaskMarksItDoneOnTheBoardAndReopenPutsItBack() async {
        let fake = FakeService()
        await fake.seedBoard(boardTask("t1", "Fix login redirect", status: "IN_REVIEW"))
        let store = CommitmentStore(service: fake, cache: cache)
        store.activate(userId: "u1")
        await store.refresh()
        store.complete("task:t1")
        await store.flush()
        var status = await fake.board["t1"]?.status
        XCTAssertEqual(status, "DONE")
        store.reopen("task:t1")
        await store.flush()
        status = await fake.board["t1"]?.status
        XCTAssertEqual(status, "IN_REVIEW")
    }

    func testRedatingABoardTaskSendsTheDay() async {
        let fake = FakeService()
        await fake.seedBoard(boardTask("t1", "Fix login redirect"))
        let store = CommitmentStore(service: fake, cache: cache)
        store.activate(userId: "u1")
        await store.refresh()
        let due = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 10))!
        store.update("task:t1", CommitmentPatch(dueAt: .set(due)))
        await store.flush()
        let day = await fake.board["t1"]?.dueDate
        XCTAssertEqual(day, "2026-11-09")
        store.snooze("task:t1", until: due)
        XCTAssertNil(store.commitment(id: "task:t1")?.snoozedUntil, "board tasks aren't snoozed")
    }

    func testAFailedBoardReadKeepsYourToDosAndTheLastBoardList() async {
        let fake = FakeService()
        await fake.seedBoard(boardTask("t1", "Fix login redirect"))
        let store = CommitmentStore(service: fake, cache: cache)
        store.activate(userId: "u1")
        await store.refresh()
        await fake.setBoardFails(true)
        store.add(text: "Book dentist")
        await store.refresh()
        XCTAssertNotNil(store.boardProblem)
        XCTAssertTrue(store.items.contains { $0.title == "Fix login redirect" })
        XCTAssertTrue(store.items.contains { $0.title == "Book dentist" })
    }
}
