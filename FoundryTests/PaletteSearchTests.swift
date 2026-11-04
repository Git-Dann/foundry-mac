import XCTest
@testable import Foundry

@MainActor
final class PaletteSearchTests: XCTestCase {
    private func item(_ title: String, _ subtitle: String? = nil, kind: PaletteItem.Kind = .action) -> PaletteItem {
        PaletteItem(id: title, title: title, subtitle: subtitle, symbol: "circle", kind: kind, action: {})
    }

    func testEmptyQueryKeepsOrder() {
        let items = [item("Today"), item("Upcoming"), item("Done")]
        XCTAssertEqual(PaletteSearch.rank(query: "  ", items: items).map(\.title), ["Today", "Upcoming", "Done"])
    }

    func testPrefixRanksBeforeContains() {
        let items = [item("Send the brief"), item("Brief Valu"), item("Debrief")]
        XCTAssertEqual(PaletteSearch.rank(query: "brief", items: items).map(\.title), ["Brief Valu", "Send the brief", "Debrief"])
    }

    func testCaseAndDiacriticInsensitive() {
        let items = [item("Call Siân"), item("Café notes")]
        XCTAssertEqual(PaletteSearch.rank(query: "SIAN", items: items).map(\.title), ["Call Siân"])
        XCTAssertEqual(PaletteSearch.rank(query: "cafe", items: items).map(\.title), ["Café notes"])
    }

    func testNoMatchIsExcluded() {
        XCTAssertTrue(PaletteSearch.rank(query: "zzz", items: [item("Today")]).isEmpty)
    }

    func testSubtitleMatchesRankLast() {
        let items = [item("Quote", "Clients"), item("Clients")]
        XCTAssertEqual(PaletteSearch.rank(query: "clients", items: items).map(\.title), ["Clients", "Quote"])
    }

    func testEveryWordMustMatch() {
        let items = [item("Send quote to Valu"), item("Send invoice")]
        XCTAssertEqual(PaletteSearch.rank(query: "valu send", items: items).map(\.title), ["Send quote to Valu"])
    }

    func testTiesKeepOriginalOrder() {
        let items = [item("Today b"), item("Today a")]
        XCTAssertEqual(PaletteSearch.rank(query: "today", items: items).map(\.title), ["Today b", "Today a"])
    }
}
