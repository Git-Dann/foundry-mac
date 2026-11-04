import AppIntents
import Foundation

/// What Foundry shows while a Focus that uses its filter is on.
enum FocusFilterMode: String, AppEnum, Sendable {
    case everything, todayOnly, boardTasksOnly

    static let defaultsKey = "focusFilter.mode"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "To-dos"
    static let caseDisplayRepresentations: [FocusFilterMode: DisplayRepresentation] = [
        .everything: "Everything",
        .todayOnly: "Today only",
        .boardTasksOnly: "Board tasks only",
    ]

    /// The mode the current Focus asked for, or everything when no Focus filter is set.
    static func current(_ defaults: UserDefaults = .standard) -> FocusFilterMode {
        defaults.string(forKey: defaultsKey).flatMap(FocusFilterMode.init(rawValue:)) ?? .everything
    }
}

/// Makes Foundry appear under System Settings › Focus › Focus filters. The system runs this
/// when a Focus starts, and again with the default value when it ends.
struct FoundryFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Foundry"
    static let description = IntentDescription("Choose which to-dos Foundry shows during this Focus.")

    @Parameter(title: "Only show", default: .everything)
    var mode: FocusFilterMode

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Foundry",
            subtitle: FocusFilterMode.caseDisplayRepresentations[mode]?.title ?? "Everything"
        )
    }

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(mode.rawValue, forKey: FocusFilterMode.defaultsKey)
        return .result()
    }
}
