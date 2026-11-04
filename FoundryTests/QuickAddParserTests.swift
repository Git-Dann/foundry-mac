import XCTest
@testable import Foundry

final class QuickAddParserTests: XCTestCase {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/London")!; return c }()
    lazy var now = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10))! // a Wednesday

    func testEverythingAtOnce() {
        let r = QuickAddParser.parse("Call Valu about the quote #sales !! ~Clients every week fri 3pm", now: now, calendar: cal)
        XCTAssertEqual(r.title, "Call Valu about the quote")
        XCTAssertEqual(r.tags, ["sales"])
        XCTAssertEqual(r.priority, 2)
        XCTAssertEqual(r.listName, "Clients")
        XCTAssertEqual(r.recurrence, .weekly)
        let c = cal.dateComponents([.weekday, .hour], from: r.dueAt!)
        XCTAssertEqual(c.weekday, 6)
        XCTAssertEqual(c.hour, 15)
    }

    func testPlainTitlesAreLeftAlone() {
        let r = QuickAddParser.parse("Review the 3 options", now: now, calendar: cal)
        XCTAssertEqual(r.title, "Review the 3 options")
        XCTAssertNil(r.dueAt)
        XCTAssertEqual(r.priority, 0)
    }

    func testTimesAndEvenings() {
        XCTAssertEqual(QuickAddParser.parseTime("3pm")?.h, 15)
        XCTAssertEqual(QuickAddParser.parseTime("12am")?.h, 0)
        XCTAssertEqual(QuickAddParser.parseTime("15:30")?.m, 30)
        XCTAssertNil(QuickAddParser.parseTime("3"), "a bare number isn't a time")
        let r = QuickAddParser.parse("Read the brief tonight", now: now, calendar: cal)
        XCTAssertTrue(r.evening)
        XCTAssertEqual(r.title, "Read the brief")
    }

    func testRepeatsAndSomeday() {
        XCTAssertEqual(QuickAddParser.parse("Invoices every 2 weeks", now: now, calendar: cal).recurrence, .every(2, .week))
        XCTAssertEqual(QuickAddParser.parse("Stand-up every weekday", now: now, calendar: cal).recurrence, .weekdays)
        let s = QuickAddParser.parse("Learn Rust someday", now: now, calendar: cal)
        XCTAssertTrue(s.someday)
        XCTAssertEqual(s.title, "Learn Rust")
    }
}
