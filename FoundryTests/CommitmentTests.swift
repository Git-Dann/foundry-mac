import XCTest
@testable import Foundry

final class CommitmentDecodingTests: XCTestCase {
    let json = """
    {"commitments":[{"id":"c1","title":"Send the deck","notes":null,"dueAt":"2026-11-07T17:00:00.000Z",
    "state":"suggested","source":"gmail","counterpart":"Acme","quote":"I'll send the deck on Friday",
    "evidenceLabel":"Re: Deck","evidenceUrl":"https://mail.google.com/mail/u/0/#sent/1","evidenceAt":"2026-11-03T10:00:00Z",
    "reason":null,"snoozedUntil":null,"doneAt":null,"createdAt":"2026-11-03T10:00:00.000Z","updatedAt":"2026-11-03T10:00:00.000Z"},
    {"id":"c2","title":"Odd one","notes":null,"dueAt":null,"state":"archived","source":"teams","counterpart":null,"quote":null,
    "evidenceLabel":null,"evidenceUrl":"javascript:alert(1)","evidenceAt":null,"reason":null,"snoozedUntil":null,"doneAt":null,
    "createdAt":"2026-11-03T10:00:00.000Z","updatedAt":"2026-11-03T10:00:00.000Z"}],
    "settings":{"gmailEnabled":true,"slackEnabled":false,"meetingsEnabled":true,"calendarEnabled":true,
    "lastSyncedAt":null,"syncing":false,"sourceStatus":{"gmail":{"ok":false,"message":"Sign in to Google again","at":"2026-11-03T10:00:00.000Z"}},
    "slackConnected":false}}
    """

    func testDecodesTheCamelCaseContract() throws {
        let r = try JSONDecoder.foundry.decode(CommitmentsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.commitments.count, 2)
        let c = r.commitments[0]
        XCTAssertEqual(c.state, .suggested)
        XCTAssertEqual(c.source, .gmail)
        XCTAssertEqual(c.quote, "I'll send the deck on Friday")
        XCTAssertNotNil(c.dueAt)
        XCTAssertEqual(c.evidenceLink?.host, "mail.google.com")
        XCTAssertEqual(r.settings.problem(for: .gmail), "Sign in to Google again")
        XCTAssertNil(r.settings.problem(for: .slack), "A switched-off source reports no problem")
    }

    func testUnknownValuesDoNotBreakTheList() throws {
        let r = try JSONDecoder.foundry.decode(CommitmentsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.commitments[1].state, .done)
        XCTAssertEqual(r.commitments[1].source, .unknown)
        XCTAssertNil(r.commitments[1].evidenceLink, "Only http(s) links open")
    }

    func testEvidenceLinksResolveRelativePathsAndRefuseOtherSchemes() {
        let base = URL(string: "https://foundry.gitwork.co.uk")!
        XCTAssertEqual(Commitment.link("/app/portal/acme", base: base)?.absoluteString, "https://foundry.gitwork.co.uk/app/portal/acme")
        XCTAssertNil(Commitment.link("//evil.example/x", base: base))
        XCTAssertNil(Commitment.link("javascript:alert(1)", base: base))
        XCTAssertNil(Commitment.link("file:///etc/passwd", base: base))
        XCTAssertEqual(Commitment.link("https://slack.com/archives/C1/p2", base: base)?.host, "slack.com")
    }

    func testPatchBodyUsesCamelCaseKeysAndNull() throws {
        let date = ISO8601DateParser.date(from: "2026-11-05T09:00:00.000Z")!
        let body = try CommitmentPatch(dueAt: .clear, state: .open, snoozedUntil: .set(date)).jsonBody()
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertEqual(text, #"{"dueAt":null,"snoozedUntil":"2026-11-05T09:00:00.000Z","state":"open"}"#)
        XCTAssertFalse(text.contains("snoozed_until"))
    }

    func testCreateBodyOmitsEmptyFields() throws {
        let text = String(decoding: try NewCommitment(title: "Call Acme", notes: "", counterpart: nil).jsonBody(), as: UTF8.self)
        XCTAssertEqual(text, #"{"title":"Call Acme"}"#)
    }

    func testSettingsRoundTripThroughTheCache() throws {
        let r = try JSONDecoder.foundry.decode(CommitmentsResponse.self, from: Data(json.utf8))
        let again = try JSONDecoder.foundry.decode(CommitmentsResponse.self, from: JSONEncoder.foundry.encode(r))
        XCTAssertEqual(again.commitments, r.commitments)
        XCTAssertEqual(again.settings, r.settings)
    }
}

final class GroupingTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/London")!; c.firstWeekday = 2; return c }()
    // Wednesday 4 Nov 2026, 10:00 London.
    lazy var now = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10))!

    func item(_ due: Date?, state: Commitment.State = .open, snoozed: Date? = nil) -> Commitment {
        var c = Commitment.local(id: UUID().uuidString, NewCommitment(title: "x", dueAt: due), now: now)
        c.state = state; c.snoozedUntil = snoozed
        return c
    }

    func testGroups() {
        func g(_ d: Date?, snoozed: Date? = nil) -> DueGroup { CommitmentGrouping.group(item(d, snoozed: snoozed), now: now, calendar: cal) }
        XCTAssertEqual(g(now.addingTimeInterval(-60)), .overdue)
        XCTAssertEqual(g(now.addingTimeInterval(3600)), .today)
        XCTAssertEqual(g(cal.date(byAdding: .day, value: 1, to: now)), .next7)
        XCTAssertEqual(g(cal.date(byAdding: .day, value: 7, to: now)), .next7)
        XCTAssertEqual(g(cal.date(byAdding: .day, value: 8, to: now)), .later)
        XCTAssertEqual(g(nil), .noDate)
        XCTAssertEqual(g(now.addingTimeInterval(-60), snoozed: now.addingTimeInterval(60)), .snoozed, "Snoozed wins over overdue")
        XCTAssertEqual(g(now.addingTimeInterval(-60), snoozed: now.addingTimeInterval(-1)), .overdue, "A finished snooze no longer hides it")
    }

    func testSectionsOnlyHoldOpenItemsAndSortSoonestFirst() {
        let later = item(now.addingTimeInterval(7200)), sooner = item(now.addingTimeInterval(3600))
        let sections = CommitmentGrouping.sections([later, item(nil, state: .done), sooner, item(nil, state: .suggested)], now: now, calendar: cal)
        XCTAssertEqual(sections.map(\.group), [.today])
        XCTAssertEqual(sections[0].items.map(\.id), [sooner.id, later.id])
    }

    func testDueNowCountsOverdueAndToday() {
        let items = [item(now.addingTimeInterval(-60)), item(now.addingTimeInterval(60)), item(cal.date(byAdding: .day, value: 2, to: now)), item(nil)]
        XCTAssertEqual(CommitmentGrouping.dueNowCount(items, now: now, calendar: cal), 2)
    }

    func testSnoozeOptions() {
        let tomorrow9 = cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9))!
        XCTAssertEqual(SnoozeOption.laterToday.until(from: now, calendar: cal), now.addingTimeInterval(3 * 3600))
        XCTAssertEqual(SnoozeOption.tomorrow.until(from: now, calendar: cal), tomorrow9)
        XCTAssertEqual(SnoozeOption.nextMonday.until(from: now, calendar: cal), cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9))!)
        let lateEvening = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 20))!
        XCTAssertEqual(SnoozeOption.laterToday.until(from: lateEvening, calendar: cal), tomorrow9, "Never snoozes into the night")
    }
}

final class DueDateParserTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/London")!; c.firstWeekday = 2; return c }()
    lazy var now = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10))! // Wednesday

    func day(_ d: Int, _ m: Int = 11, _ y: Int = 2026, hour: Int = 17) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func parse(_ s: String) -> DueDateParser.Result { DueDateParser.parse(s, now: now, calendar: cal) }

    func testReadsTheEndOfTheLine() {
        XCTAssertEqual(parse("Send Acme the deck fri"), .init(title: "Send Acme the deck", dueAt: day(6), matched: "fri"))
        XCTAssertEqual(parse("Call Priya tomorrow").dueAt, day(5))
        XCTAssertEqual(parse("Ship it today").dueAt, day(4))
        XCTAssertEqual(parse("Ring mum tonight").dueAt, day(4, hour: 20))
        XCTAssertEqual(parse("Draft the brief by thursday"), .init(title: "Draft the brief", dueAt: day(5), matched: "thursday"))
        XCTAssertEqual(parse("Write it up in 3 days").dueAt, day(7))
        XCTAssertEqual(parse("Plan Q1 in 2 weeks").dueAt, day(18))
        XCTAssertEqual(parse("Invoice 23 nov").dueAt, day(23))
        XCTAssertEqual(parse("Invoice nov 23").dueAt, day(23))
        XCTAssertEqual(parse("Renew domain 2 jan").dueAt, day(2, 1, 2027), "A passed date means next year")
    }

    func testWeekdayMeansTheNextOne() {
        XCTAssertEqual(parse("Standup notes wed").dueAt, day(11), "On a Wednesday, 'wed' is next week")
        XCTAssertEqual(parse("Retro next fri").dueAt, day(13), "'next fri' is the Friday of next week")
        XCTAssertEqual(parse("Plan the sprint next week").dueAt, day(9))
    }

    func testLeavesOrdinaryTitlesAlone() {
        XCTAssertNil(parse("Review the 3 options").dueAt)
        XCTAssertNil(parse("Call Monday.com about billing").dueAt)
        XCTAssertNil(parse("today").dueAt, "A lone date word is the title, not a date")
        XCTAssertNil(parse("Book 31 feb").dueAt)
        XCTAssertEqual(parse("  Email Sian  ").title, "Email Sian")
    }
}

final class NotificationPlanTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/London")!; return c }()
    lazy var now = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10))!

    func item(_ due: Date?, state: Commitment.State = .open) -> Commitment {
        var c = Commitment.local(id: UUID().uuidString, NewCommitment(title: "Send the deck", dueAt: due), now: now)
        c.state = state
        return c
    }

    func testNudgesOnlyOpenFutureDues() {
        let future = item(now.addingTimeInterval(3600)), past = item(now.addingTimeInterval(-3600)),
            done = item(now.addingTimeInterval(3600), state: .done), suggestion = item(now.addingTimeInterval(3600), state: .suggested)
        let plan = NotificationPlan.make(items: [future, past, done, suggestion], now: now,
                                         prefs: .init(digestEnabled: false), calendar: cal)
        XCTAssertEqual(plan.map(\.commitmentId), [future.id])
    }

    func testSnoozeMovesTheNudge() {
        var c = item(now.addingTimeInterval(3600))
        c.snoozedUntil = now.addingTimeInterval(7200)
        let plan = NotificationPlan.make(items: [c], now: now, prefs: .init(digestEnabled: false), calendar: cal)
        XCTAssertEqual(plan.first?.date, now.addingTimeInterval(7200))
    }

    func testSuggestionsNeverPingOnTheirOwnAndQuietMorningsSendNothing() {
        let plan = NotificationPlan.make(items: [item(nil)], now: now, prefs: .init(overdueEnabled: false), calendar: cal)
        XCTAssertTrue(plan.isEmpty)
        let withReview = NotificationPlan.make(items: [item(nil, state: .suggested)], now: now, prefs: .init(overdueEnabled: false), calendar: cal)
        XCTAssertEqual(withReview.count, 1, "One digest mentions what's waiting; nothing else")
        XCTAssertEqual(withReview.first?.body, "1 to review.")
    }

    func testDigestCountsThatDay() {
        let tomorrow5 = cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 17))!
        let plan = NotificationPlan.make(items: [item(tomorrow5), item(now.addingTimeInterval(-60))], now: now,
                                         prefs: .init(overdueEnabled: false), calendar: cal)
        let first = plan.first { $0.kind == .digest }
        XCTAssertEqual(first?.date, cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9)))
        XCTAssertEqual(first?.body, "1 due today, 1 overdue.")
    }
}

final class WidgetSnapshotTests: XCTestCase {
    func testHoldsTitlesOnlyAndSkipsSnoozedAndFarOff() {
        let now = Date()
        var near = Commitment.local(id: "a", NewCommitment(title: "Near", dueAt: now.addingTimeInterval(1800), notes: "secret"), now: now)
        near.quote = "private words"
        var snoozed = Commitment.local(id: "b", NewCommitment(title: "Snoozed", dueAt: now), now: now)
        snoozed.snoozedUntil = now.addingTimeInterval(3600)
        let far = Commitment.local(id: "c", NewCommitment(title: "Far", dueAt: now.addingTimeInterval(86400 * 10)), now: now)
        let snap = WidgetPublisher.snapshot([near, snoozed, far], signedIn: true, now: now)
        XCTAssertEqual(snap.items.map(\.id), ["a"])
        let encoded = String(decoding: try! JSONEncoder().encode(snap), as: UTF8.self)
        XCTAssertFalse(encoded.contains("secret") || encoded.contains("private words"))
        XCTAssertEqual(WidgetPublisher.snapshot([near], signedIn: false, now: now).items, [])
    }
}

final class SourceProblemTests: XCTestCase {
    // The exact message production returned on 4 Nov 2026.
    let credit = #"The AI read failed: 400 {"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits."},"request_id":"req_011CghzJ99FFwaYPmCZVf5gt"}"#

    func testOutOfCreditReadsAsASentence() {
        let s = SourceProblem.plain(credit)
        XCTAssertFalse(s.contains("{"))
        XCTAssertTrue(s.contains("credit has run out"))
    }

    func testOtherJSONErrorsShowOnlyTheirMessage() {
        let s = SourceProblem.plain(#"The AI read failed: 500 {"error":{"message":"Something odd happened"}}"#)
        XCTAssertEqual(s, "The AI read failed: Something odd happened")
    }

    func testPlainMessagesAreKept() {
        XCTAssertEqual(SourceProblem.plain("Your Foundry email isn't on a Slack account"), "Your Foundry email isn't on a Slack account")
    }

    func testSummaryNamesTheFailedSources() {
        let bad = CommitmentSourceStatus(ok: false, message: credit, at: nil)
        let good = CommitmentSourceStatus(ok: true, message: "40 open action items", at: nil)
        let s = SourceProblem.summary(["meeting": bad, "calendar": bad])!
        XCTAssertTrue(s.hasPrefix("Meeting notes and Calendar are paused."), s)
        XCTAssertTrue(s.contains("credit has run out"))
        XCTAssertNil(SourceProblem.summary(["meeting": good]))
        // Email and Slack aren't read by this app any more, so their old failures never show.
        XCTAssertNil(SourceProblem.summary(["gmail": bad, "slack": bad, "meeting": good]))
    }
}
