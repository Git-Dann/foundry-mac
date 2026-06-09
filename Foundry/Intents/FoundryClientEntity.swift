import AppIntents

/// App Intents entity for a client.
struct FoundryClientEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Client")
    static var defaultQuery = FoundryClientQuery()

    var id: String
    var name: String
    var slug: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct FoundryClientQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [FoundryClientEntity] {
        let client = foundryIntentClient()
        let all = (try? await client.listClients()) ?? []
        let wanted = Set(identifiers)
        return all.filter { wanted.contains($0.id) }
            .map { FoundryClientEntity(id: $0.id, name: $0.name, slug: $0.slug) }
    }

    @MainActor
    func suggestedEntities() async throws -> [FoundryClientEntity] {
        let client = foundryIntentClient()
        let all = (try? await client.listClients()) ?? []
        return all.prefix(25).map { FoundryClientEntity(id: $0.id, name: $0.name, slug: $0.slug) }
    }
}
