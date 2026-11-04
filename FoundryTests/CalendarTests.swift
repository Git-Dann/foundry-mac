import XCTest
@testable import Foundry

final class CalendarLayoutTests: XCTestCase {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    func span(_ id: String, _ startMin: Double, _ endMin: Double) -> CalendarLayout.Span {
        .init(id: id, start: base.addingTimeInterval(startMin * 60), end: base.addingTimeInterval(endMin * 60))
    }

    func testSeparateBlocksTakeTheFullWidth() {
        let s = CalendarLayout.slots([span("a", 0, 30), span("b", 30, 60)])
        XCTAssertEqual(s["a"], .init(column: 0, columns: 1))
        XCTAssertEqual(s["b"], .init(column: 0, columns: 1), "Touching isn't overlapping")
    }

    func testOverlapsSitSideBySideAndReuseFreedColumns() {
        // a: 0-60, b: 15-45, c: 50-90 → a and b overlap; c reuses b's column; all three are one group.
        let s = CalendarLayout.slots([span("a", 0, 60), span("b", 15, 45), span("c", 50, 90)])
        XCTAssertEqual(s["a"]?.column, 0)
        XCTAssertEqual(s["b"]?.column, 1)
        XCTAssertEqual(s["c"]?.column, 1)
        XCTAssertEqual(Set([s["a"]!.columns, s["b"]!.columns, s["c"]!.columns]), [2])
    }

    func testDropSnapsToQuarterHoursInsideTheDay() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/London")!
        let day = cal.date(from: DateComponents(year: 2026, month: 11, day: 4))!
        let at = { (y: Double) in cal.dateComponents([.hour, .minute], from: CalendarLayout.time(atY: y, on: day, calendar: cal)) }
        let h = CalendarLayout.hourHeight
        XCTAssertEqual(at(14 * h + h * 0.3).hour, 14); XCTAssertEqual(at(14 * h + h * 0.3).minute, 15)
        XCTAssertEqual(at(-50).hour, 0)
        XCTAssertEqual(at(30 * h).hour, 23); XCTAssertEqual(at(30 * h).minute, 45)
    }

    func testWeekTitles() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/London")!; cal.firstWeekday = 2
        cal.locale = Locale(identifier: "en_GB")
        let wed = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
        let week = CalendarLayout.days(around: wed, mode: .week, calendar: cal)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(cal.component(.day, from: week[0]), 2, "Monday 2 Nov")
        XCTAssertEqual(CalendarLayout.subtitle(for: week, calendar: cal), "2026, Week 45")
        XCTAssertEqual(CalendarLayout.days(around: wed, mode: .day, calendar: cal).count, 1)
    }
}

final class CalendarDecodingTests: XCTestCase {
    func testDecodesTheEndpointIncludingAllDayDates() throws {
        let json = #"{"connected":true,"connectedAs":"dan@gitwork.co.uk","events":[{"id":"a","title":"Fellas x Gitwork","start":"2026-11-04T14:30:00.000Z","end":"2026-11-04T15:00:00.000Z","allDay":false,"location":null,"meetLink":"https://meet.google.com/x","htmlLink":"https://www.google.com/calendar/event?eid=1","attendees":2},{"id":"b","title":"Bank holiday","start":"2026-12-25","end":"2026-12-26","allDay":true,"location":null,"meetLink":null,"htmlLink":null,"attendees":0}]}"#
        let r = try JSONDecoder.foundry.decode(CalendarEventsResponse.self, from: Data(json.utf8))
        let events = r.appEvents()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].meetLink?.host, "meet.google.com")
        XCTAssertTrue(events[1].isAllDay)
        XCTAssertEqual(Calendar.current.component(.day, from: events[1].start), 25, "A calendar day stays that day locally")
    }

    func testNotConnectedCarriesTheReason() throws {
        let r = try JSONDecoder.foundry.decode(CalendarEventsResponse.self, from: Data(#"{"connected":false,"reason":"Google isn't connected for you.","events":[]}"#.utf8))
        XCTAssertFalse(r.connected)
        XCTAssertEqual(r.reason, "Google isn't connected for you.")
    }
}
