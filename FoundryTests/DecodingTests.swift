import XCTest
@testable import Foundry

/// Validates the Codable models decode the live API's bare-JSON shapes, including the
/// fractional-second ISO-8601 dates and lenient enum fallback.
final class DecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.foundry.decode(type, from: Data(json.utf8))
    }

    func testProposalListDecodes() throws {
        let json = """
        {"proposals":[{"id":"p1","title":"Acme Proposal","clientName":"Acme","productName":null,
        "status":"SENT","updatedAt":"2026-06-09T08:33:00.000Z","templateName":null,"ownerName":"Dan",
        "documentNumber":"DOC-1","documentType":"PROPOSAL","labels":["q3"],"parentId":null}]}
        """
        let response = try decode(ProposalListResponse.self, json)
        XCTAssertEqual(response.proposals.count, 1)
        let item = response.proposals[0]
        XCTAssertEqual(item.status, .sent)
        XCTAssertEqual(item.documentType, .proposal)
        XCTAssertEqual(item.labels, ["q3"])
        XCTAssertNil(item.productName)
    }

    func testFractionalAndPlainDates() {
        XCTAssertNotNil(ISO8601DateParser.date(from: "2026-06-09T08:33:00.000Z"))
        XCTAssertNotNil(ISO8601DateParser.date(from: "2026-06-09T08:33:00Z"))
        XCTAssertNil(ISO8601DateParser.date(from: "not-a-date"))
    }

    func testUnknownEnumFallsBackNotThrows() throws {
        let json = """
        {"proposals":[{"id":"p2","title":"X","clientName":null,"productName":null,
        "status":"SOME_NEW_STATUS","updatedAt":"2026-06-09T08:33:00Z","templateName":null,"ownerName":null,
        "documentNumber":null,"documentType":"WEIRD","labels":[],"parentId":null}]}
        """
        let response = try decode(ProposalListResponse.self, json)
        XCTAssertEqual(response.proposals[0].status, .unknown)
        XCTAssertEqual(response.proposals[0].documentType, .unknown)
    }

    func testClientListDecodes() throws {
        let json = """
        {"clients":[{"id":"c1","name":"Acme","slug":"acme","logoUrl":null,
        "createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-06-01T00:00:00.000Z",
        "proposalCount":3,"source":"MANUAL","status":"ACTIVE","googleDriveFolderUrl":null,
        "clickupUrl":null,"hasCareClient":true,"repoUrls":["https://github.com/x/y"]}]}
        """
        let response = try decode(ClientListResponse.self, json)
        XCTAssertEqual(response.clients[0].status, .active)
        XCTAssertEqual(response.clients[0].proposalCount, 3)
        XCTAssertTrue(response.clients[0].hasCareClient)
    }

    func testRateCardDecodes() throws {
        let json = """
        {"people":[{"id":"r1","workspaceId":"w1","seedIdentifier":null,"name":"Jo","area":"iOS",
        "sourceRate":450,"sourceCurrencyCode":"GBP","billingPeriod":"DAY","archivedAt":null,
        "createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-02T00:00:00Z"}]}
        """
        let response = try decode(RateCardListResponse.self, json)
        XCTAssertEqual(response.people[0].billingPeriod, .day)
        XCTAssertEqual(response.people[0].sourceRate, 450)
        XCTAssertFalse(response.people[0].isArchived)
    }

    func testHealthDecodes() throws {
        let json = #"{"ok":true,"service":"foundry-by-gitwork","version":"0.1.0","timestamp":"2026-06-09T08:33:00.000Z"}"#
        let health = try decode(HealthStatus.self, json)
        XCTAssertTrue(health.ok)
        XCTAssertEqual(health.service, "foundry-by-gitwork")
    }

    func testCodeClearStatsDecodes() throws {
        let json = """
        {"total":42,"byStatus":[{"status":"PLACED","count":5}],"avgThis":78.5,"avgLast":null,
        "passRateThis":0.6,"recheckDue":2,"recentActivity":[]}
        """
        let stats = try decode(CodeClearStats.self, json)
        XCTAssertEqual(stats.total, 42)
        XCTAssertEqual(stats.byStatus.first?.status, .placed)
        XCTAssertEqual(stats.recheckDue, 2)
    }
}
