import SwiftUI

/// Foundry for Mac — native SwiftUI app entry point.
///
/// macOS 26 (Tahoe). Liquid Glass is provided automatically by the standard system
/// components used throughout (sidebar, toolbar, sheets, controls) — the app never
/// hand-rolls blur/opacity/shadow "glass".
@main
struct FoundryApp: App {
    @State private var model = AppModel()
    @State private var updates = UpdateController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            FoundryCommands(model: model, checkForUpdates: { updates.checkForUpdates() })
        }

        // Controlled WebKit bridge: hosted Foundry screens open in their own native window.
        WindowGroup("Foundry Web", id: "foundry-web", for: WebDestination.self) { $destination in
            if let destination {
                FoundryWebScreen(destination: destination)
                    .environment(model)
            }
        }
        .defaultSize(width: 1120, height: 780)

        Settings {
            FoundrySettingsView()
                .environment(model)
                .environment(updates)
        }
    }
}
