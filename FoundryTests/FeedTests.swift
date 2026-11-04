import XCTest
@testable import Foundry

final class FeedTests: XCTestCase {
    let base = URL(string: "https://foundry.gitwork.co.uk")!
    let now = Date()

    func msg(_ id: String, _ author: String, ago hours: Double, client: String = "Wedge") -> DeskMessageDTO {
        DeskMessageDTO(id: id, author: author, text: "Can you check the course list?", ts: now.addingTimeInterval(-hours * 3600),
                       clientName: client, clientSlug: client.lowercased(), link: nil)
    }

    func testMentionsLeadAndYourOwnMessagesAreLeftOut() {
        let items = FeedRules.build(
            mentions: [msg("m1", "Luke McFarland", ago: 5)],
            messages: [msg("a", "Dan", ago: 1), msg("b", "Hassaan Bin Sajjad", ago: 2), msg("m1", "Luke McFarland", ago: 5)],
            myName: "dan", cleared: [], now: now, base: base
        )
        XCTAssertEqual(items.map(\.id), ["m1", "b"], "mention first, no duplicate, not my own message")
        XCTAssertEqual(items.first?.kind, .mention)
    }

    func testClearedAndOldMessagesDropOut() {
        let items = FeedRules.build(
            mentions: [], messages: [msg("old", "Luke", ago: 24 * 8), msg("c", "Luke", ago: 1), msg("d", "Luke", ago: 2)],
            myName: nil, cleared: ["c"], now: now, base: base
        )
        XCTAssertEqual(items.map(\.id), ["d"])
    }

    func testWithoutASlackLinkItOpensTheClientInPortal() {
        let items = FeedRules.build(mentions: [], messages: [msg("c", "Luke", ago: 1)], myName: nil, cleared: [], now: now, base: base)
        XCTAssertEqual(items.first?.link?.absoluteString, "https://foundry.gitwork.co.uk/app/portal/wedge")
        XCTAssertTrue(items.first!.suggestedToDo.hasPrefix("Reply to Luke (Wedge): "))
    }
}

final class DisplayTests: XCTestCase {
    func c(_ title: String) -> Commitment {
        Commitment(id: "x", title: title, notes: nil, dueAt: nil, state: .open, source: .calendar, counterpart: nil, quote: nil,
                   evidenceLabel: nil, evidenceUrl: nil, evidenceAt: nil, reason: nil, snoozedUntil: nil, doneAt: nil,
                   createdAt: Date(), updatedAt: Date())
    }

    func testFollowUpsNamePeopleNotAddresses() {
        let l = Display.lines(for: c("Follow up with luke.mcfarland@bigwedgegolf.com after “Wedge x Gitwork”"))
        XCTAssertEqual(l.title, "Follow up with Luke McFarland")
        XCTAssertEqual(l.subtitle, "bigwedgegolf.com · After “Wedge x Gitwork”")
        XCTAssertNil(Display.organisation(ofEmail: "nasir@gmail.com"), "a personal mail service names no company")
    }

    func testABoardTagMovesToTheSubtitle() {
        XCTAssertEqual(Display.lines(for: c("[Handover] Confirm DPA signed")), .init(title: "Confirm DPA signed", subtitle: "Handover"))
        XCTAssertEqual(Display.lines(for: c("Send the deck")).title, "Send the deck")
    }
}

final class MailItemTests: XCTestCase {
    func testMailDecodesAndBecomesAReplyToDo() throws {
        let json = #"{"connected":true,"messages":[{"id":"m1","threadId":"t1","fromName":"Luke McFarland","fromEmail":"luke@bigwedgegolf.com","subject":"Course list for Q1","snippet":"Can you check…","date":"2026-11-04T10:00:00.000Z","unread":true,"link":"https://mail.google.com/mail/?authuser=dan%40gitwork.co.uk#all/t1"}]}"#
        let box = try JSONDecoder.foundry.decode(MailInboxDTO.self, from: Data(json.utf8))
        XCTAssertEqual(box.messages.first?.suggestedToDo, "Reply to Luke McFarland: Course list for Q1")
        XCTAssertEqual(box.messages.first?.url?.host, "mail.google.com")
    }
}
