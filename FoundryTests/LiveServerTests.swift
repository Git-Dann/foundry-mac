import XCTest
@testable import Foundry

/// Runs the app's real API client, store and offline queue against a running Foundry server.
/// Skipped unless `FOUNDRY_IT_TOKEN` (a mobile JWT) is set; `FOUNDRY_IT_BASE` defaults to
/// http://localhost:3100. Pass them to xcodebuild as `TEST_RUNNER_FOUNDRY_IT_TOKEN=…`.
///
/// It changes data on that server (adds, completes, deletes), so never point it at production
/// with a real account.
@MainActor
final class LiveServerTests: XCTestCase {
    var token: String!
    var base: URL!

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let t = env["FOUNDRY_IT_TOKEN"], !t.isEmpty else { throw XCTSkip("FOUNDRY_IT_TOKEN not set") }
        token = t
        base = URL(string: env["FOUNDRY_IT_BASE"] ?? "http://localhost:3100")!
        XCTAssertNotEqual(base.host, "foundry.gitwork.co.uk", "Never run this against production")
        Commitment.webBase = base
    }

    func api(_ url: URL? = nil) -> CommitmentsAPI {
        let u = url ?? base!, t = token!
        return CommitmentsAPI(baseURL: { u }, token: { t })
    }

    func testTheWholeLoopAgainstTheServer() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "live-\(UUID().uuidString)")
        let store = CommitmentStore(service: api(), cache: CommitmentCache(directory: dir))
        store.activate(userId: "live")
        await store.refresh()
        XCTAssertNil(store.lastError)
        XCTAssertNotNil(store.loadedAt)

        // Add, with a due date read from the words.
        let local = try XCTUnwrap(store.add(text: "Send Fairway the staging link fri"))
        XCTAssertTrue(local.isLocalOnly)
        await store.flush()
        let added = try XCTUnwrap(store.items.first { $0.title == "Send Fairway the staging link" })
        XCTAssertFalse(added.isLocalOnly, "Got the server's id")
        var server = try await api().list().commitments.first { $0.id == added.id }
        XCTAssertEqual(server?.dueAt, local.dueAt, "Due date round-trips")
        XCTAssertEqual(Calendar.current.component(.weekday, from: try XCTUnwrap(server?.dueAt)), 6)

        // Complete, then undo.
        store.complete(added.id); await store.flush()
        server = try await api().list().commitments.first { $0.id == added.id }
        XCTAssertEqual(server?.state, .done); XCTAssertNotNil(server?.doneAt)
        store.reopen(added.id); await store.flush()
        server = try await api().list().commitments.first { $0.id == added.id }
        XCTAssertEqual(server?.state, .open)

        // Snooze until tomorrow 09:00, then wake.
        let until = SnoozeOption.tomorrow.until(from: Date())
        store.snooze(added.id, until: until); await store.flush()
        server = try await api().list().commitments.first { $0.id == added.id }
        XCTAssertEqual(server?.snoozedUntil?.timeIntervalSince1970 ?? 0, until.timeIntervalSince1970, accuracy: 1)
        store.unsnooze(added.id); await store.flush()
        server = try await api().list().commitments.first { $0.id == added.id }
        XCTAssertNil(server?.snoozedUntil)

        // Check sources: the seeded meeting's action items arrive as suggestions with evidence.
        await store.checkSources()
        let suggestions = CommitmentGrouping.suggestions(store.items).filter { $0.source == .meeting }
        XCTAssertGreaterThanOrEqual(suggestions.count, 2, store.lastCheckSummary ?? store.lastError ?? "no summary")
        for s in suggestions {
            XCTAssertEqual(s.evidenceLabel, "Fairway weekly check-in")
            XCTAssertEqual(s.counterpart, "Fairway Golf")
            XCTAssertEqual(s.evidenceLink?.absoluteString, base.absoluteString + "/app/portal/fairway")
        }
        print("LIVE check summary:", store.lastCheckSummary ?? "-")
        print("LIVE source status:", store.settings.sourceStatus.mapValues { "\($0.ok) \($0.message)" })

        // Accept one, dismiss the other ("Not mine").
        guard suggestions.count >= 2 else { return XCTFail("Needs two fresh meeting suggestions; reset the test data") }
        let accept = suggestions[0], dismiss = suggestions[1]
        store.accept(accept.id); store.dismiss(dismiss.id); await store.flush()
        let after = try await api().list().commitments
        XCTAssertEqual(after.first { $0.id == accept.id }?.state, .open)
        XCTAssertEqual(after.first { $0.id == dismiss.id }?.state, .dismissed)

        // A dismissed suggestion isn't suggested again on the next read.
        await store.checkSources()
        XCTAssertFalse(store.items.contains { $0.state == .suggested && $0.title == dismiss.title })

        // Suggestions can't be deleted: the store refuses, and so does the server.
        store.delete(accept.id)
        XCTAssertNotNil(store.commitment(id: accept.id))
        do { try await api().delete(id: accept.id); XCTFail("Server should refuse") } catch let e as AppError {
            print("LIVE delete-suggestion refused:", e.localizedDescription)
        }

        // Typed-in ones can.
        store.delete(added.id); await store.flush()
        let remaining = try await api().list().commitments
        XCTAssertFalse(remaining.contains { $0.id == added.id })

        // Settings.
        var s = store.settings
        s.calendarEnabled = false
        await store.updateSettings(s)
        let off = try await api().list().settings.calendarEnabled
        XCTAssertEqual(off, false)
        s.calendarEnabled = true
        await store.updateSettings(s)
        let on = try await api().list().settings.calendarEnabled
        XCTAssertEqual(on, true)
        XCTAssertNil(store.lastError, store.lastError ?? "")
    }

    func testEditsMadeOfflineAreSentWhenTheServerIsBack() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "live-off-\(UUID().uuidString)")
        let dead = URL(string: "http://127.0.0.1:9")! // nothing listens on the discard port
        let offline = CommitmentStore(service: api(dead), cache: CommitmentCache(directory: dir))
        offline.activate(userId: "live")
        let local = try XCTUnwrap(offline.add(text: "Written while offline tomorrow"))
        offline.update(local.id, CommitmentPatch(notes: .set("from the train")))
        await offline.flush()
        XCTAssertTrue(offline.isOffline)
        XCTAssertEqual(offline.pendingCount, 1)

        // Relaunch with the server reachable: the cache carries the queued create.
        let online = CommitmentStore(service: api(), cache: CommitmentCache(directory: dir))
        online.activate(userId: "live")
        XCTAssertEqual(online.pendingCount, 1)
        await online.refresh()
        XCTAssertEqual(online.pendingCount, 0)
        let server = try await api().list().commitments.first { $0.title == "Written while offline" }
        XCTAssertEqual(server?.notes, "from the train")
        if let id = server?.id { try await api().delete(id: id) }
    }

    func testUnknownTokenIsUnauthorized() async throws {
        let bad = CommitmentsAPI(baseURL: { [base] in base! }, token: { "not-a-token" })
        do { _ = try await bad.list(); XCTFail("Expected 401") } catch let e as AppError {
            XCTAssertTrue(e.isUnauthorized, e.localizedDescription)
        }
    }
}
