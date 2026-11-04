import AppIntents
import Foundation

/// "Add commitment" for Spotlight, Shortcuts and Siri. Adds to the list like quick add does;
/// it never sends, replies or books anything.
struct AddCommitmentIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Commitment"
    static let description = IntentDescription("Adds a promise to your Foundry commitments.")
    static let openAppWhenRun = false

    @Parameter(title: "Commitment", requestValueDialog: "What did you promise?")
    var title: String

    @Parameter(title: "Due", description: "Optional. Words like “fri” at the end of the commitment also work.")
    var due: Date?

    @Parameter(title: "For", description: "Who it's for, if anyone.")
    var counterpart: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$title)") {
            \.$due
            \.$counterpart
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard model.auth.isSignedIn else {
            throw CommitmentIntentError.signedOut
        }
        let parsed = DueDateParser.parse(title)
        let cleanTitle = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw CommitmentIntentError.empty }
        let dueAt = due ?? parsed.dueAt
        model.store.add(NewCommitment(
            title: String(cleanTitle.prefix(200)),
            dueAt: dueAt,
            counterpart: counterpart?.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        await model.store.flush()
        let when = dueAt.map { " for \($0.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))" } ?? ""
        return .result(dialog: "Added “\(cleanTitle)”\(when).")
    }
}

struct OpenCommitmentsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Commitments"
    static let description = IntentDescription("Opens your commitments in Foundry.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.openMainWindow()
        return .result()
    }
}

enum CommitmentIntentError: Error, CustomLocalizedStringResourceConvertible {
    case signedOut, empty

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .signedOut: "Open Foundry and sign in first."
        case .empty: "The commitment needs a few words."
        }
    }
}

struct FoundryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddCommitmentIntent(),
            phrases: ["Add a commitment in \(.applicationName)", "Add to my \(.applicationName) commitments"],
            shortTitle: "Add Commitment",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: OpenCommitmentsIntent(),
            phrases: ["Show my \(.applicationName) commitments"],
            shortTitle: "Show Commitments",
            systemImageName: "checklist"
        )
    }
}
