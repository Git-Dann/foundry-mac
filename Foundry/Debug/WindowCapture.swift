#if DEBUG
import AppKit
import SwiftUI
import WidgetKit

/// `Foundry --demo --capture <dir>`: opens the real window and the real menu-bar panel with
/// sample data, in light then dark, and saves what is on screen. Uses the window server's image
/// of this app's own windows, so no Screen Recording permission is needed.
@MainActor
enum WindowCapture {
    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        // `--debug-callback <foundry://auth-callback#token=…>`: the same handler the browser hits.
        if let c = args.firstIndex(of: "--debug-callback"), c + 1 < args.count, let url = URL(string: args[c + 1]) {
            AppModel.shared.handleURL(url)
        }
        guard let i = args.firstIndex(of: "--capture"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            let model = AppModel.shared
            try? await Task.sleep(for: .seconds(3)) // let the first refresh land
            for (name, look) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                NSApp.appearance = NSAppearance(named: look)
                model.selection = .today
                model.selectedCommitmentId = model.store.items.first { $0.source == .meeting && $0.state == .open }?.id
                model.openMainWindow()
                try? await Task.sleep(for: .seconds(1.5))
                if let w = mainWindow() {
                    w.setFrame(NSRect(x: 80, y: 80, width: 1180, height: 720), display: true)
                    try? await Task.sleep(for: .seconds(1))
                    save(w, to: dir.appending(path: "window-\(name).png"))
                    model.selection = .today
                    model.selectedCommitmentId = model.store.items.first { $0.isBoardTask && $0.state == .open }?.id
                    try? await Task.sleep(for: .seconds(1))
                    save(w, to: dir.appending(path: "window-suggestions-\(name).png"))
                    model.selection = .calendar
                    w.setFrame(NSRect(x: 80, y: 80, width: 1440, height: 860), display: true)
                    try? await Task.sleep(for: .seconds(1.5))
                    save(w, to: dir.appending(path: "calendar-\(name).png"))
                    model.selection = .foundry
                    w.setFrame(NSRect(x: 80, y: 80, width: 1180, height: 720), display: true)
                    try? await Task.sleep(for: .seconds(4))
                    save(w, to: dir.appending(path: "foundry-\(name).png"))
                    model.selection = .today
                    w.setFrame(NSRect(x: 80, y: 80, width: 1180, height: 720), display: true)
                }
                // The real panel and widget views, in on-screen windows with the system's popover
                // material, so vibrancy and dark mode render as they do from the menu bar.
                await hosted(MenuBarPanel().environment(model), width: 360, height: nil, to: dir.appending(path: "menubar-\(name).png"))
                let snap = WidgetPublisher.snapshot(model.store.items, signedIn: true)
                for (fam, label, size) in [(WidgetFamily.systemSmall, "small", CGSize(width: 170, height: 170)), (.systemMedium, "medium", CGSize(width: 364, height: 170)), (.systemLarge, "large", CGSize(width: 364, height: 382))] {
                    await hosted(TodayWidgetView(snapshot: snap, date: Date(), family: fam).padding(16).tint(Color("AccentColor")),
                                 width: size.width, height: size.height, radius: 22, to: dir.appending(path: "widget-\(label)-\(name).png"))
                }
                QuickAddPanelController.shared.show()
                try? await Task.sleep(for: .seconds(1))
                if let p = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible && $0.frame.width == 560 }) {
                    save(p, to: dir.appending(path: "quickadd-\(name).png"))
                }
                QuickAddPanelController.shared.close()
            }
            let names = ["--"] + NSApp.windows.map { "\($0.className) \($0.frame) visible=\($0.isVisible)" }
            try? names.joined(separator: "\n").write(to: dir.appending(path: "windows.txt"), atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }

    private static func hosted<V: View>(_ view: V, width: CGFloat, height: CGFloat?, radius: CGFloat = 12, to url: URL) async {
        let host = NSHostingView(rootView: view.frame(width: width, height: height))
        let size = CGSize(width: width, height: height ?? host.fittingSize.height)
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = radius
        effect.layer?.masksToBounds = true
        host.frame = effect.bounds
        effect.addSubview(host)
        let w = NSPanel(contentRect: NSRect(x: 200, y: 200, width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.contentView = effect
        w.orderFrontRegardless()
        try? await Task.sleep(for: .seconds(1))
        save(w, to: url)
        w.orderOut(nil)
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible }
    }

    private static func statusButton() -> NSStatusBarButton? {
        for w in NSApp.windows where w.className.contains("StatusBar") {
            if let b = find(NSStatusBarButton.self, in: w.contentView) { return b }
        }
        return nil
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let v = view as? T { return v }
        for s in view.subviews { if let f = find(type, in: s) { return f } }
        return nil
    }

    private static func save(_ window: NSWindow, to url: URL) {
        guard let handle = dlopen(nil, RTLD_NOW), let sym = dlsym(handle, "CGWindowListCreateImage") else { return }
        let create = unsafeBitCast(sym, to: CreateImage.self)
        // .null rect, optionIncludingWindow (8), bestResolution (8) | boundsIgnoreFraming (1)
        guard let image = create(.null, 8, UInt32(window.windowNumber), 9)?.takeRetainedValue() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
