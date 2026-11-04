import XCTest
@testable import Foundry

final class PlanTests: XCTestCase {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/London")!; return c }()
    lazy var now = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10))!

    func todo(_ id: String, start: Int? = nil, due: Int? = nil, evening: Bool = false, someday: Bool = false,
              list: String? = nil, tags: [String] = [], priority: Int = 0, order: Double = 0) -> Commitment {
        func day(_ d: Int) -> Date { cal.date(byAdding: .day, value: d, to: cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 17))!)! }
        return Commitment(id: id, title: id, notes: nil, dueAt: due.map(day), state: .open, source: .manual, counterpart: nil,
                          quote: nil, evidenceLabel: nil, evidenceUrl: nil, evidenceAt: nil, reason: nil, snoozedUntil: nil,
                          doneAt: nil, createdAt: now, updatedAt: now, listId: list, tags: tags, priority: priority,
                          startAt: start.map(day), evening: evening, someday: someday, orderKey: order)
    }

    func testTodaySplitsOverdueDayAndEvening() {
        let items = [todo("late", due: -1), todo("start", start: 0), todo("eve", start: 0, evening: true),
                     todo("tomorrow", start: 1), todo("some", start: 0, someday: true)]
        let s = Plan.today(items, now: now, calendar: cal)
        XCTAssertEqual(s.map(\.id), ["overdue", "today", "evening"])
        XCTAssertEqual(s.flatMap(\.items).map(\.id), ["late", "start", "eve"], "someday and tomorrow stay out of Today")
    }

    func testInboxIsUnsortedCaptureOnly() {
        let items = [todo("loose"), todo("listed", list: "l1"), todo("dated", due: 2), todo("some", someday: true)]
        XCTAssertEqual(Plan.inbox(items, now: now).map(\.id), ["loose"])
    }

    func testUpcomingIsByDayThenMonth() {
        let items = [todo("t1", start: 1), todo("t3", due: 3), todo("far", due: 40), todo("today", start: 0)]
        let s = Plan.upcoming(items, now: now, calendar: cal)
        XCTAssertEqual(s.first?.title, "Tomorrow")
        XCTAssertEqual(s.flatMap(\.items).map(\.id), ["t1", "t3", "far"])
        XCTAssertEqual(s.count, 3)
    }

    func testFiltersCombine() {
        let f = TodoFilter(tags: ["sales"], minPriority: 2)
        XCTAssertTrue(f.matches(todo("a", tags: ["sales", "q4"], priority: 3), now: now))
        XCTAssertFalse(f.matches(todo("b", tags: ["sales"], priority: 1), now: now))
        XCTAssertFalse(f.matches(todo("c", priority: 3), now: now))
    }

    func testManualOrderWinsInALIst() {
        let s = Plan.filtered([todo("b", list: "l", order: 2), todo("a", list: "l", order: 1)], filter: .list("l"), lists: [], now: now)
        XCTAssertEqual(s.first?.items.map(\.id), ["a", "b"])
    }

    func testRecurrenceRulesRoundTrip() {
        for r in Recurrence.presets + [.every(3, .day), .every(2, .month)] {
            XCTAssertEqual(Recurrence(rule: r.rule), r)
        }
        XCTAssertNil(Recurrence(rule: "every:0:day"))
        XCTAssertNil(Recurrence(rule: "hourly"))
    }
}

final class ReminderPlanTests: XCTestCase {
    func testAReminderIsScheduledEvenWithNudgesOff() {
        let now = Date()
        var c = Commitment.local(id: "r1", NewCommitment(title: "Call Valu"), now: now)
        c.remindAt = now.addingTimeInterval(3600)
        var prefs = NotificationPreferences()
        prefs.overdueEnabled = false
        prefs.digestEnabled = false
        let plan = NotificationPlan.make(items: [c], now: now, prefs: prefs)
        XCTAssertEqual(plan.map(\.id), ["commitments.remind.r1"])
    }
}
