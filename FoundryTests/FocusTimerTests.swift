import XCTest
@testable import Foundry

final class FocusTimerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testRemainingCountsDownWhileRunning() {
        let clock = FocusClock(duration: 25 * 60, startedAt: t0)
        XCTAssertEqual(clock.remaining(at: t0), 1500)
        XCTAssertEqual(clock.remaining(at: t0 + 600), 900)
        XCTAssertEqual(clock.progress(at: t0 + 750), 0.5, accuracy: 0.0001)
        XCTAssertEqual(clock.endDate, t0 + 1500)
    }

    func testNeverGoesBelowZeroOrAboveDuration() {
        let clock = FocusClock(duration: 60, startedAt: t0)
        XCTAssertEqual(clock.remaining(at: t0 + 3600), 0)
        XCTAssertTrue(clock.isFinished(at: t0 + 60))
        XCTAssertEqual(clock.remaining(at: t0 - 30), 60)
    }

    func testPauseFreezesTimeAndResumeMovesTheEnd() {
        var clock = FocusClock(duration: 1500, startedAt: t0)
        clock.pause(at: t0 + 300)
        XCTAssertNil(clock.endDate)
        XCTAssertEqual(clock.remaining(at: t0 + 300), 1200)
        XCTAssertEqual(clock.remaining(at: t0 + 1000), 1200, "paused time doesn't count")
        clock.resume(at: t0 + 1000)
        XCTAssertEqual(clock.remaining(at: t0 + 1000), 1200)
        XCTAssertEqual(clock.remaining(at: t0 + 1100), 1100)
        XCTAssertEqual(clock.endDate, t0 + 1500 + 700)
    }

    func testRepeatedPausesAddUp() {
        var clock = FocusClock(duration: 600, startedAt: t0)
        clock.pause(at: t0 + 100); clock.resume(at: t0 + 200)
        clock.pause(at: t0 + 300); clock.pause(at: t0 + 350) // second pause is ignored
        clock.resume(at: t0 + 400)
        XCTAssertEqual(clock.pausedTotal, 200)
        XCTAssertEqual(clock.remaining(at: t0 + 500), 300)
        clock.resume(at: t0 + 500) // resuming while running does nothing
        XCTAssertEqual(clock.pausedTotal, 200)
    }

    func testFormat() {
        XCTAssertEqual(FocusSession.format(1500), "25:00")
        XCTAssertEqual(FocusSession.format(59.2), "01:00")
        XCTAssertEqual(FocusSession.format(3725), "1:02:05")
    }

    @MainActor
    func testSessionPersistsAndResumesAfterRelaunch() {
        let suite = "focus.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = t0
        let first = FocusSession(defaults: defaults, now: { now }, notifies: false)
        first.lengthMinutes = 15
        first.start(todoId: "c1", todoTitle: "Send the proposal")
        now = t0 + 120
        first.pause()

        now = t0 + 400
        let second = FocusSession(defaults: defaults, now: { now }, notifies: false)
        XCTAssertEqual(second.state, .paused)
        XCTAssertEqual(second.todoTitle, "Send the proposal")
        XCTAssertEqual(second.remaining(at: now), 780)
        second.resume()
        XCTAssertEqual(second.state, .running)
        XCTAssertEqual(second.lengthMinutes, 15)
    }

    @MainActor
    func testFinishingCountsASessionAndStartsABreak() {
        let suite = "focus.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = t0
        let session = FocusSession(defaults: defaults, now: { now }, notifies: false)
        session.start()
        now = t0 + 25 * 60
        session.finishIfDue()
        XCTAssertEqual(session.state, .onBreak)
        XCTAssertEqual(session.completedToday, 1)
        now += 5 * 60
        session.finishIfDue()
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.completedToday, 1)
    }

    @MainActor
    func testSessionThatEndedWhileClosedIsCountedNotResumed() {
        let suite = "focus.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = t0
        FocusSession(defaults: defaults, now: { now }, notifies: false).start()
        now = t0 + 3600
        let relaunched = FocusSession(defaults: defaults, now: { now }, notifies: false)
        XCTAssertEqual(relaunched.state, .idle)
        XCTAssertEqual(relaunched.completedToday, 1)
    }

    func testFocusFilterModeDefaultsToEverything() {
        let suite = "filter.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(FocusFilterMode.current(defaults), .everything)
        defaults.set("todayOnly", forKey: FocusFilterMode.defaultsKey)
        XCTAssertEqual(FocusFilterMode.current(defaults), .todayOnly)
    }
}
