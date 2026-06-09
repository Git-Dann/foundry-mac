import SwiftUI
import AppKit

/// Handles the `foundry://` sign-in callback at the AppKit level. A SwiftUI `WindowGroup`
/// opens a NEW window for each incoming URL via `.onOpenURL`, which spawned a duplicate window
/// on sign-in; routing the URL through the app delegate instead delivers it to the running
/// instance without opening a window.
final class FoundryAppDelegate: NSObject, NSApplicationDelegate {
    var onURL: ((URL) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { onURL?($0) }
    }
}

/// Foundry for Mac — native SwiftUI app entry point.
///
/// macOS 26 (Tahoe). Liquid Glass is provided automatically by the standard system
/// components used throughout (sidebar, toolbar, sheets, controls) — the app never
/// hand-rolls blur/opacity/shadow "glass".
@main
struct FoundryApp: App {
    @State private var model = AppModel()
    @State private var updates = UpdateController()
    @NSApplicationDelegateAdaptor(FoundryAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                // foundry://auth-callback#token=… is delivered via the app delegate (above),
                // not .onOpenURL, so the sign-in callback doesn't open a second window.
                .task { appDelegate.onURL = { url in model.auth.handleCallback(url) } }
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

        // Calendar — its own window (two-way Google), opened from the toolbar / menu bar.
        WindowGroup("Calendar", id: "calendar") {
            CalendarWindow().environment(model)
        }
        .defaultSize(width: 820, height: 680)

        // Menu-bar quick glance — runs in-process so the AI-spend figures are live (no App Group
        // needed, unlike the WidgetKit widgets which require a signed build to share data).
        MenuBarExtra("Foundry", systemImage: "hammer.fill") {
            MenuBarContent(checkForUpdates: { updates.checkForUpdates() })
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            FoundrySettingsView()
                .environment(model)
                .environment(updates)
        }
    }
}
