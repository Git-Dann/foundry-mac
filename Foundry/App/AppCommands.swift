import SwiftUI

/// Native menu commands + keyboard shortcuts.
///
/// - New Proposal ⌘N  (File)
/// - Check for Updates…  (App menu; wired to Sparkle in FoundryApp)
/// - Refresh ⌘R, Search ⌘F, Open Foundry Web ⌘L  (View)
/// - Settings ⌘,  is provided automatically by the `Settings` scene.
struct FoundryCommands: Commands {
    let model: AppModel
    /// Supplied by FoundryApp once the Sparkle updater exists.
    var checkForUpdates: (() -> Void)?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Proposal") { model.requestNewProposal() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!model.auth.isSignedIn)
        }

        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { checkForUpdates?() }
                .disabled(checkForUpdates == nil)
        }

        CommandGroup(after: .sidebar) {
            Button("Refresh") { model.requestRefresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!model.auth.isSignedIn)
            Button("Search") { model.requestSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!model.auth.isSignedIn)
            Divider()
            Button("Open Foundry Web") { model.openWeb() }
                .keyboardShortcut("l", modifiers: .command)
        }
    }
}
