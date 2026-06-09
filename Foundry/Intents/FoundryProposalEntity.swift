import AppIntents

/// App Intents entity for a proposal — surfaces proposals to Shortcuts and Spotlight.
struct FoundryProposalEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Proposal")
    static var defaultQuery = FoundryProposalQuery()

    var id: String
    var title: String
    var clientName: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: clientName.map { "\($0)" } ?? ""
        )
    }
}

struct FoundryProposalQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [FoundryProposalEntity] {
        let client = foundryIntentClient()
        var result: [FoundryProposalEntity] = []
        for id in identifiers {
            if let proposal = try? await client.getProposal(id: id) {
                result.append(FoundryProposalEntity(id: proposal.id, title: proposal.title, clientName: proposal.clientName))
            }
        }
        return result
    }

    @MainActor
    func suggestedEntities() async throws -> [FoundryProposalEntity] {
        let client = foundryIntentClient()
        let items = (try? await client.listProposals(sort: "updatedAt:desc")) ?? []
        return items.prefix(20).map { FoundryProposalEntity(id: $0.id, title: $0.title, clientName: $0.clientName) }
    }
}
