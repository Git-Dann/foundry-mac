import XCTest
@testable import Foundry

final class HabitStatsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        c.firstWeekday = 2
        return c
    }()

    /// Noon on a day in November 2026 (Wednesday the 4th is "today").
    private func day(_ d: Int, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: d, hour: 12))!
    }

    private var today: Date { day(4) }

    func testStreakEndingToday() {
        let days: Set = [day(2), day(3), day(4)]
        XCTAssertEqual(HabitStats.currentStreak(days: days, today: today, calendar: calendar), 3)
    }

    func testStreakEndingYesterdayStillCounts() {
        let days: Set = [day(1), day(2), day(3)]
        XCTAssertEqual(HabitStats.currentStreak(days: days, today: today, calendar: calendar), 3)
    }

    func testGapBreaksTheStreak() {
        let days: Set = [day(30, month: 10), day(31, month: 10), day(2), day(3), day(4)]
        XCTAssertEqual(HabitStats.currentStreak(days: days, today: today, calendar: calendar), 3)
        XCTAssertEqual(HabitStats.currentStreak(days: [day(2)], today: today, calendar: calendar), 0)
        XCTAssertEqual(HabitStats.currentStreak(days: [], today: today, calendar: calendar), 0)
    }

    func testStreakCrossesMonthAndClockChange() {
        // British Summer Time ended on 25 October 2026; days either side still chain.
        let days: Set = Set((20...31).map { day($0, month: 10) } + (1...4).map { day($0) })
        XCTAssertEqual(HabitStats.currentStreak(days: days, today: today, calendar: calendar), 16)
    }

    func testWeekRunsMondayToSunday() {
        let week = HabitStats.weekDays(containing: today, calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertTrue(calendar.isDate(week[0], inSameDayAs: day(2)))
        XCTAssertTrue(calendar.isDate(week[6], inSameDayAs: day(8)))
    }

    func testWeekCount() {
        let days: Set = [day(1), day(2), day(3), day(8), day(9)]
        XCTAssertEqual(HabitStats.weekCount(days: days, containing: today, calendar: calendar), 3) // 2, 3, 8
        XCTAssertEqual(HabitStats.weekCount(days: days, containing: day(1), calendar: calendar), 1)
    }

    func testWeeklyRatesAreOldestFirstAndCapped() {
        let days: Set = [day(2), day(3), day(4), day(27, month: 10)]
        let rates = HabitStats.weeklyRates(days: days, targetPerWeek: 2, today: today, calendar: calendar)
        XCTAssertEqual(rates.count, 12)
        XCTAssertEqual(rates.last?.count, 3)
        XCTAssertEqual(rates.last?.rate, 1)
        XCTAssertEqual(rates[10].count, 1)
        XCTAssertEqual(rates[10].rate, 0.5)
        XCTAssertEqual(rates.first?.count, 0)
        let overall = HabitStats.completionRate(days: days, targetPerWeek: 2, today: today, calendar: calendar)
        XCTAssertEqual(overall, 1.5 / 12, accuracy: 0.0001)
    }

    @MainActor
    func testStoreTogglesDaysInMemory() {
        let store = HabitStore(inMemory: true, calendar: calendar)
        let habit = store.add(name: "  Walk  ", symbol: "figure.walk", colorName: "green", targetPerWeek: 9)
        XCTAssertEqual(habit?.name, "Walk")
        XCTAssertEqual(habit?.targetPerWeek, 7)
        let id = habit!.id
        store.toggle(id, on: today, now: today)
        XCTAssertTrue(store.isDone(id, on: today))
        store.toggle(id, on: day(5), now: today) // tomorrow can't be ticked
        XCTAssertEqual(store.days(for: id).count, 1)
        store.toggle(id, on: today, now: today)
        XCTAssertFalse(store.isDone(id, on: today))
        store.archive(id)
        XCTAssertTrue(store.habits.isEmpty)
        XCTAssertNil(store.add(name: "   ", symbol: "x", colorName: "blue", targetPerWeek: 3))
    }
}
