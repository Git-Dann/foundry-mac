import AppIntents

/// Open the Foundry app.
struct OpenFoundryIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Foundry"
    static var description = IntentDescription("Open the Foundry app.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult { .result() }
}

/// Create a new proposal from Shortcuts / Spotlight.
struct CreateProposalIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Proposal"
    static var description = IntentDescription("Create a new Foundry proposal.")
    static var openAppWhenRun = true

    @Parameter(title: "Title")
    var proposalTitle: String

    static var parameterSummary: some ParameterSummary {
        Summary("Create proposal \(\.$proposalTitle)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<FoundryProposalEntity> & ProvidesDialog {
        let client = foundryIntentClient()
        let created = try await client.createProposal(ProposalCreateInput(title: proposalTitle))
        let entity = FoundryProposalEntity(id: created.id, title: created.title, clientName: created.clientName)
        return .result(value: entity, dialog: "Created “\(created.title)”.")
    }
}

/// Search proposals; returns matching entities (usable as Shortcuts output).
struct SearchProposalsIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Proposals"
    static var description = IntentDescription("Find Foundry proposals by keyword.")

    @Parameter(title: "Query")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search proposals for \(\.$query)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[FoundryProposalEntity]> {
        let client = foundryIntentClient()
        let items = (try? await client.listProposals(search: query)) ?? []
        let entities = items.map { FoundryProposalEntity(id: $0.id, title: $0.title, clientName: $0.clientName) }
        return .result(value: entities)
    }
}

/// Surfaces the intents to Shortcuts + Spotlight.
struct FoundryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenFoundryIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open Foundry",
            systemImageName: "hammer.fill"
        )
        AppShortcut(
            intent: SearchProposalsIntent(),
            phrases: ["Search \(.applicationName) proposals"],
            shortTitle: "Search Proposals",
            systemImageName: "doc.text.magnifyingglass"
        )
        AppShortcut(
            intent: CreateProposalIntent(),
            phrases: ["Create a \(.applicationName) proposal"],
            shortTitle: "New Proposal",
            systemImageName: "square.and.pencil"
        )
    }
}
