#if DEBUG
import AppKit
import SwiftUI
import WidgetKit

/// `Foundry --render-screenshots <dir>` draws each surface with sample data, in light and dark,
/// to PNGs and quits. These are the real views at their real sizes, hosted offscreen; menu-bar
/// chrome and the desktop around them are not included.
@MainActor
enum ScreenshotRenderer {
    static func runIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--render-screenshots"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let model = AppModel.shared
        let sample = SampleData.items(now: Date())
        model.selection = .today
        model.selectedCommitmentId = sample.first(where: { $0.source == .meeting && $0.state == .open })?.id

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let ap = NSAppearance(named: appearance)!
            render(MenuBarPanel().environment(model), size: nil, width: 360, appearance: ap, to: dir.appending(path: "menubar-\(name).png"))
            render(MainWindow().environment(model), size: CGSize(width: 1180, height: 720), appearance: ap, to: dir.appending(path: "window-\(name).png"), titled: true)
            model.selection = .suggestions
            model.selectedCommitmentId = CommitmentGrouping.suggestions(sample).first?.id
            render(MainWindow().environment(model), size: CGSize(width: 1180, height: 720), appearance: ap, to: dir.appending(path: "window-suggestions-\(name).png"), titled: true)
            model.selection = .today
            model.selectedCommitmentId = sample.first(where: { $0.source == .meeting && $0.state == .open })?.id
            let snap = WidgetPublisher.snapshot(sample, signedIn: true)
            for (fam, size) in [(WidgetFamily.systemSmall, CGSize(width: 170, height: 170)), (.systemMedium, CGSize(width: 364, height: 170)), (.systemLarge, CGSize(width: 364, height: 382))] {
                let view = TodayWidgetView(snapshot: snap, date: Date(), family: fam)
                    .padding(16)
                    .frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .tint(Color("AccentColor"))
                render(view, size: size, appearance: ap, to: dir.appending(path: "widget-\(fam == .systemSmall ? "small" : fam == .systemMedium ? "medium" : "large")-\(name).png"))
            }
            render(QuickAddPanelView(onClose: {}).environment(model), size: nil, width: 560, appearance: ap, to: dir.appending(path: "quickadd-\(name).png"))
        }
        NSApp.terminate(nil)
        return true
    }

    private static func render<V: View>(_ view: V, size: CGSize?, width: CGFloat? = nil, appearance: NSAppearance, to url: URL, titled: Bool = false) {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, appearance.name == .darkAqua ? .dark : .light))
        let fitting = host.fittingSize
        let frameSize = size ?? CGSize(width: width ?? fitting.width, height: fitting.height)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: frameSize),
            styleMask: titled ? [.titled, .fullSizeContentView, .closable, .miniaturizable, .resizable] : [.borderless],
            backing: .buffered, defer: false
        )
        window.appearance = appearance
        window.contentView = host
        window.setContentSize(frameSize)
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}

/// Believable sample commitments for screenshots and previews. Not used with a real account.
enum SampleData {
    static func items(now: Date) -> [Commitment] {
        let cal = Calendar.current
        func at(_ days: Int, _ hour: Int) -> Date {
            cal.date(bySettingHour: hour, minute: 0, second: 0, of: cal.date(byAdding: .day, value: days, to: now)!)!
        }
        func c(_ id: String, _ title: String, due: Date?, state: Commitment.State = .open, source: Commitment.Source = .manual,
               who: String? = nil, quote: String? = nil, label: String? = nil, url: String? = nil) -> Commitment {
            Commitment(id: id, title: title, notes: nil, dueAt: due, state: state, source: source, counterpart: who,
                       quote: quote, evidenceLabel: label, evidenceUrl: url, evidenceAt: now.addingTimeInterval(-86_400),
                       reason: nil, snoozedUntil: nil, doneAt: state == .done ? now.addingTimeInterval(-3600) : nil,
                       createdAt: now.addingTimeInterval(-200_000), updatedAt: now)
        }
        return [
            c("a", "Send Northwind the revised timeline", due: at(-1, 17), source: .gmail, who: "Priya, Northwind",
              quote: "I'll send over the revised timeline by Monday so you can share it with the board.",
              label: "Re: Phase two timing", url: "https://mail.google.com/"),
            c("b", "Share the staging link with the Fairway team", due: at(0, 17), source: .meeting, who: "Fairway Golf",
              quote: "Dan to share the staging link once the booking flow is merged.", label: "Weekly check-in", url: "https://foundry.gitwork.co.uk/"),
            c("c", "Review Harry's quote for the retainer", due: at(0, 16)),
            c("d", "Book a call to walk through the handover docs", due: at(2, 17), source: .calendar, who: "Acme Health",
              quote: nil, label: "Handover review"),
            c("e", "Write up the Pulse findings for Cadenza", due: at(4, 17)),
            c("f", "Draft the case study outline", due: at(12, 17)),
            c("g", "Look into the push notification delay", due: nil, who: "Big Wedge"),
            c("s1", "Send the signed SOW back to Leisure Tech", due: nil, state: .suggested, source: .slack, who: "Leisure Tech",
              quote: "Yep, I'll get the signed SOW back to you this afternoon.", label: "#leisure-tech", url: "https://slack.com/"),
            c("s2", "Introduce Sian to the PollenIQ team", due: nil, state: .suggested, source: .gmail, who: "PollenIQ",
              quote: "Happy to introduce you to Sian, who looks after our HR side, later this week.", label: "Re: Onboarding", url: "https://mail.google.com/"),
            c("x", "Send the October invoice", due: at(-2, 12), state: .done),
        ]
    }

    static let settings = CommitmentSettings(
        gmailEnabled: true, slackEnabled: true, meetingsEnabled: true, calendarEnabled: true,
        lastSyncedAt: Date().addingTimeInterval(-1200), syncing: false,
        sourceStatus: [
            "gmail": .init(ok: true, message: "Read 14 sent emails", at: Date()),
            "slack": .init(ok: false, message: "Your Foundry email isn't on a Slack account", at: Date()),
        ],
        slackConnected: false
    )
}
#endif
