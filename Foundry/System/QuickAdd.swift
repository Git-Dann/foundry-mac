import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A system-wide shortcut for quick add. Uses Carbon's `RegisterEventHotKey`, which needs no
/// Accessibility permission (unlike watching every keystroke).
@MainActor
final class GlobalHotKey {
    struct Combo: Equatable {
        var keyCode: UInt32
        var modifiers: UInt32
        var label: String
        /// ⌃⌥Space: free on a stock Mac (Spotlight is ⌘Space, Finder search ⌥⌘Space).
        static let quickAdd = Combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), label: "⌃⌥Space")
    }

    static let shared = GlobalHotKey()
    static let enabledKey = "hotkey.quickAdd.enabled"

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    private(set) var registered = false

    func register(_ combo: Combo = .quickAdd, action: @escaping () -> Void) {
        unregister()
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in GlobalHotKey.shared.action?() }
            return noErr
        }, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x46_44_52_59), id: 1) // "FDRY"
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        registered = status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil; handler = nil; registered = false
    }
}

/// The small floating field the hotkey opens. Enter adds, Escape closes, nothing else happens.
@MainActor
final class QuickAddPanelController {
    static let shared = QuickAddPanelController()
    private var panel: NSPanel?

    func toggle() {
        if let panel, panel.isVisible { close(); return }
        show()
    }

    func show() {
        let model = AppModel.shared
        if panel == nil {
            let p = KeyablePanel(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 96),
                styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isMovableByWindowBackground = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.standardWindowButton(.closeButton)?.isHidden = true
            p.standardWindowButton(.miniaturizeButton)?.isHidden = true
            p.standardWindowButton(.zoomButton)?.isHidden = true
            p.contentView = NSHostingView(rootView: QuickAddPanelView(onClose: { [weak self] in self?.close() }).environment(model))
            panel = p
        }
        guard let panel else { return }
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - f.height * 0.28))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() { panel?.orderOut(nil) }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

struct QuickAddPanelView: View {
    @Environment(AppModel.self) private var model
    let onClose: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.tint)
                TextField("I promised to…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit(add)
                    .onExitCommand(perform: onClose)
            }
            DueHint(text: text, signedIn: model.auth.isSignedIn)
                .padding(.leading, 36)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 560)
        .ignoresSafeArea()
        .onAppear { focused = true; text = "" }
    }

    private func add() {
        guard model.auth.isSignedIn, model.store.add(text: text) != nil else { return }
        text = ""
        onClose()
    }
}

/// "Due Friday 21 Nov" under a quick-add field, so the person sees what the date words became.
struct DueHint: View {
    let text: String
    var signedIn = true

    var body: some View {
        let parsed = QuickAddParser.parse(text)
        Group {
            if !signedIn {
                Text("Sign in to Foundry to add to-dos.")
            } else if !parsed.chips.isEmpty {
                Text(parsed.chips.joined(separator: "  ·  "))
            } else {
                Text("Return to add. Try “fri 3pm”, “#tag”, “!!”, “~List”, “every week”.")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}
