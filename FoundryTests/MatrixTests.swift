import XCTest
@testable import Foundry

final class MatrixTests: XCTestCase {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/London")!; return c }()
    lazy var now = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10))!

    func at(day: Int, hour: Int = 17) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: 4 + day, hour: hour))!
    }

    func todo(_ id: String = "a", due: Date? = nil, start: Date? = nil, priority: Int = 0) -> Commitment {
        Commitment(id: id, title: id, notes: nil, dueAt: due, state: .open, source: .manual, counterpart: nil,
                   quote: nil, evidenceLabel: nil, evidenceUrl: nil, evidenceAt: nil, reason: nil, snoozedUntil: nil,
                   doneAt: nil, createdAt: now, updatedAt: now, priority: priority, startAt: start)
    }

    func q(_ c: Commitment) -> Quadrant { MatrixRules.quadrant(c, now: now, calendar: cal) }

    func testQuadrants() {
        XCTAssertEqual(q(todo(due: at(day: 1), priority: 3)), .doNow)
        XCTAssertEqual(q(todo(due: at(day: 5), priority: 2)), .schedule)
        XCTAssertEqual(q(todo(due: at(day: 1), priority: 1)), .delegate)
        XCTAssertEqual(q(todo(priority: 1)), .later)
    }

    func testOverdueCountsAsUrgent() {
        XCTAssertEqual(q(todo(due: at(day: -10))), .delegate)
        XCTAssertEqual(q(todo(due: at(day: -1), priority: 2)), .doNow)
    }

    func testTwoDayBoundary() {
        XCTAssertEqual(q(todo(due: at(day: 2, hour: 10))), .delegate, "exactly two days is urgent")
        XCTAssertEqual(q(todo(due: at(day: 2, hour: 11))), .later)
    }

    func testPlannedTodayOrEarlierIsUrgent() {
        XCTAssertEqual(q(todo(start: at(day: 0, hour: 0))), .delegate)
        XCTAssertEqual(q(todo(start: at(day: -3, hour: 0))), .delegate)
        XCTAssertEqual(q(todo(start: at(day: 1, hour: 0))), .later)
    }

    func testMovingToImportantRaisesPriority() {
        let p = MatrixRules.patch(moving: todo(priority: 1), to: .schedule, now: now, calendar: cal)
        XCTAssertEqual(p, CommitmentPatch(priority: 3))
    }

    func testMovingToNotImportantClearsPriority() {
        let p = MatrixRules.patch(moving: todo(due: at(day: 5), priority: 3), to: .later, now: now, calendar: cal)
        XCTAssertEqual(p, CommitmentPatch(priority: 0))
    }

    func testMovingToUrgentSetsDueTodayAtFive() {
        let p = MatrixRules.patch(moving: todo(priority: 2), to: .doNow, now: now, calendar: cal)
        XCTAssertEqual(p?.dueAt, .set(at(day: 0)))
        XCTAssertNil(p?.priority, "already important")
    }

    func testMovingToNotUrgentPushesDueAWeek() {
        let p = MatrixRules.patch(moving: todo(due: at(day: -1), priority: 3), to: .schedule, now: now, calendar: cal)
        XCTAssertEqual(p?.dueAt, .set(at(day: 7)))
        XCTAssertNil(p?.priority)
    }

    func testMovingToNotUrgentAlsoMovesPlannedDay() {
        let c = todo(start: at(day: 0, hour: 0))
        let p = MatrixRules.patch(moving: c, to: .later, now: now, calendar: cal)
        XCTAssertEqual(p?.startAt, .set(at(day: 7, hour: 0)))
        let moved = p!.applied(to: c, now: now)
        XCTAssertEqual(q(moved), .later)
    }

    func testSameQuadrantIsNil() {
        XCTAssertNil(MatrixRules.patch(moving: todo(due: at(day: 1), priority: 3), to: .doNow, now: now, calendar: cal))
    }

    func testBoardTaskNeverChangesPriority() {
        let board = todo("task:1", priority: 0)
        XCTAssertNil(MatrixRules.patch(moving: board, to: .schedule, now: now, calendar: cal), "only priority would change")
        let p = MatrixRules.patch(moving: board, to: .doNow, now: now, calendar: cal)
        XCTAssertEqual(p, CommitmentPatch(dueAt: .set(at(day: 0))), "only the deadline moves")
        let urgent = todo("task:2", due: at(day: 1), priority: 3)
        XCTAssertEqual(MatrixRules.patch(moving: urgent, to: .later, now: now, calendar: cal),
                       CommitmentPatch(dueAt: .set(at(day: 7))))
    }

    func testEveryMoveLandsInTarget() {
        let seeds = [todo(priority: 0), todo(due: at(day: -2), priority: 3), todo(start: at(day: 0, hour: 0), priority: 2), todo(due: at(day: 9), priority: 1)]
        for c in seeds {
            for target in Quadrant.allCases {
                let moved = MatrixRules.patch(moving: c, to: target, now: now, calendar: cal).map { $0.applied(to: c, now: now) } ?? c
                XCTAssertEqual(q(moved), target, "\(c.id) → \(target)")
            }
        }
    }
}
