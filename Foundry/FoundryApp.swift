import SwiftUI
import AppKit

/// Routes `foundry://` links (sign-in callback, widget and notification taps) to the running
/// app. A SwiftUI `.onOpenURL` on a `WindowGroup` opens a new window per URL, so it is handled here.
final class FoundryAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in urls.forEach { AppModel.shared.handleURL($0) } }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            #if DEBUG
            if ScreenshotRenderer.runIfRequested() { return }
            WindowCapture.runIfRequested()
            #endif
            FoundryApp.applyHotKey(UserDefaults.standard.object(forKey: GlobalHotKey.enabledKey) as? Bool ?? true)
        }
    }

    /// Closing the window leaves the menu-bar extra running; that's where most use happens.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Foundry for Mac: your commitments, in the menu bar and a window.
///
/// System controls only. Liquid Glass comes from the standard sidebar, toolbar, menus and
/// buttons; the app never draws its own blur or glass.
@main
struct FoundryApp: App {
    @State private var model = AppModel.shared
    @State private var updates = UpdateController()
    @NSApplicationDelegateAdaptor(FoundryAppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Foundry", id: "main") {
            MainWindow().environment(model)
        }
        .defaultSize(width: 1080, height: 700)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { CommitmentCommands(model: model, checkForUpdates: { updates.checkForUpdates() }) }

        MenuBarExtra {
            MenuBarPanel().environment(model)
        } label: {
            MenuBarLabel().environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .environment(updates)
        }
    }

    @MainActor
    static func applyHotKey(_ on: Bool) {
        if on {
            GlobalHotKey.shared.register { QuickAddPanelController.shared.toggle() }
        } else {
            GlobalHotKey.shared.unregister()
        }
    }
}

/// Keyboard first: ⌘N new, ⌘K search, Space complete (in the list), ⌘⌫ dismiss, ⌘S snooze,
/// ⌘R refresh, ⇧⌘R check sources.
struct CommitmentCommands: Commands {
    let model: AppModel
    var checkForUpdates: () -> Void

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…", action: checkForUpdates)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Commitment") {
                if model.selection != .today && model.selection != .upcoming { model.selection = .today }
                model.openMainWindow()
                model.requestQuickAddFocus()
            }
            .keyboardShortcut("n")
            .disabled(!model.auth.isSignedIn)
            Button("Quick Add…") { QuickAddPanelController.shared.show() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!model.auth.isSignedIn)
        }
        CommandMenu("To-do") {
            let selected = model.selectedCommitmentId.flatMap { model.store.commitment(id: $0) }
            Button(selected?.state == .suggested ? "Add to My To-dos" : "Mark Done") {
                guard let c = selected else { return }
                if c.state == .suggested { model.store.accept(c.id) } else { model.complete(c.id) }
            }
            .disabled(selected == nil || !(selected?.state == .open || selected?.state == .suggested))
            Button("Snooze Until Tomorrow") {
                if let c = selected { model.store.snooze(c.id, until: SnoozeOption.tomorrow.until(from: Date())) }
            }
            .keyboardShortcut("s")
            .disabled(selected?.state != .open)
            Menu("Snooze") {
                ForEach(SnoozeOption.allCases) { o in
                    Button(o.title) { if let c = selected { model.store.snooze(c.id, until: o.until(from: Date())) } }
                }
            }
            .disabled(selected?.state != .open)
            Button(selected?.state == .suggested ? "Not Mine" : "Dismiss") {
                // While typing, ⌘⌫ keeps its text meaning (delete to the start of the line).
                if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isEditable {
                    editor.deleteToBeginningOfLine(nil)
                    return
                }
                if let c = selected { model.store.dismiss(c.id) }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(selected == nil || selected?.state == .dismissed || selected?.state == .done)
            Divider()
            Button("Undo Done") { model.undoComplete() }
                .disabled(model.lastCompleted == nil)
        }
        CommandGroup(after: .sidebar) {
            Button("Search") { model.openMainWindow(); model.requestSearchFocus() }
                .keyboardShortcut("k")
            Button("Refresh") { Task { await model.store.refresh() } }
                .keyboardShortcut("r")
            Button("Check Sources Now") { Task { await model.store.checkSources() } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
                Button(item.title) { model.selection = item; model.openMainWindow() }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
        }
    }
}
