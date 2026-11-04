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
