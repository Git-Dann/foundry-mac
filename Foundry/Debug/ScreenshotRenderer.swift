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
            model.selection = .upcoming
            model.selectedCommitmentId = sample.first(where: { $0.isBoardTask })?.id
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
            let full = CGSize(width: 1100, height: 720)
            render(KanbanView().environment(model), size: full, appearance: ap, to: dir.appending(path: "board-\(name).png"))
            render(MatrixView().environment(model), size: full, appearance: ap, to: dir.appending(path: "matrix-\(name).png"))
            render(FocusView(todoId: "e").environment(model), size: CGSize(width: 800, height: 640), appearance: ap, to: dir.appending(path: "focus-\(name).png"))
            render(HabitsView().environment(model), size: CGSize(width: 800, height: 560), appearance: ap, to: dir.appending(path: "habits-\(name).png"))
            render(CommitmentDetail(id: "c").environment(model), size: CGSize(width: 640, height: 1100), appearance: ap, to: dir.appending(path: "detail-\(name).png"))
            model.selection = .upcoming
            render(MainWindow().environment(model), size: CGSize(width: 1280, height: 760), appearance: ap, to: dir.appending(path: "upcoming-\(name).png"), titled: true)
            model.selection = .today
        }
        NSApp.terminate(nil)
        return true
    }

    static func render<V: View>(_ view: V, size: CGSize?, width: CGFloat? = nil, appearance: NSAppearance, to url: URL, titled: Bool = false) {
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
        // Far off every display and fully transparent: rendering must never put a window on screen.
        window.setFrameOrigin(NSPoint(x: -40_000, y: -40_000))
        window.alphaValue = 0
        window.ignoresMouseEvents = true
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
    static let lists: [TodoList] = [
        TodoList(id: "l1", name: "Clients", color: "blue", symbol: "briefcase", area: "Work", orderKey: 0, archived: false),
        TodoList(id: "l2", name: "Hiring", color: "purple", symbol: "person.2", area: "Work", orderKey: 1, archived: false),
        TodoList(id: "l3", name: "Home", color: "green", symbol: "house", area: "Personal", orderKey: 2, archived: false),
    ]

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
        func board(_ id: String, _ title: String, due: Date?, client: String, status: String) -> Commitment {
            Commitment(id: Commitment.boardPrefix + id, title: title, notes: nil, dueAt: due, state: .open, source: .board,
                       counterpart: client, quote: nil, evidenceLabel: "\(client) board", evidenceUrl: "/app/portal/x/tasks",
                       evidenceAt: nil, reason: nil, snoozedUntil: nil, doneAt: nil,
                       createdAt: now.addingTimeInterval(-300_000), updatedAt: now, boardStatus: status)
        }
        var items = [
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
            board("t1", "Get Azure resource group access", due: at(0, 17), client: "Campfire", status: "DOING"),
            board("t2", "Book the handover call with Absurd", due: at(2, 17), client: "Campfire", status: "TODO"),
            board("t3", "Retry payment flow on Android", due: at(-1, 17), client: "Wedge", status: "IN_REVIEW"),
        ]
        func tweak(_ id: String, _ f: (inout Commitment) -> Void) {
            if let i = items.firstIndex(where: { $0.id == id }) { f(&items[i]) }
        }
        tweak("a") { $0.listId = "l1"; $0.priority = 3; $0.tags = ["sales"] }
        tweak("b") { $0.listId = "l1"; $0.startAt = cal.startOfDay(for: now); $0.priority = 2 }
        tweak("c") {
            $0.listId = "l2"; $0.startAt = cal.startOfDay(for: now); $0.evening = true; $0.recurrence = "weekly"
            $0.tags = ["hiring", "q4"]; $0.remindAt = at(0, 18)
            $0.notes = "## Before the call\nCheck the **day rate** against the rate card.\n\n- Last year's quote\n- [ ] Harry's notes\n- [x] Budget sign-off"
            $0.checklist = [ChecklistItem(text: "Read the quote", done: true), ChecklistItem(text: "Compare with rate card"), ChecklistItem(text: "Reply to Harry")]
        }
        tweak("e") { $0.listId = "l1"; $0.priority = 1 }
        tweak("f") { $0.someday = true; $0.dueAt = nil; $0.listId = "l3" }
        tweak("g") { $0.listId = "l1"; $0.tags = ["bug"] }
        return items
    }

    /// A believable week of meetings around the sample commitments.
    static func events(week: [Date]) -> [CalendarEvent] {
        let cal = Calendar.current
        func at(_ dayIndex: Int, _ h: Int, _ m: Int = 0) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: week[min(dayIndex, week.count - 1)])!
        }
        func e(_ id: String, _ title: String, _ d: Int, _ h: Int, _ m: Int, minutes: Int, people: Int = 2, meet: Bool = true) -> CalendarEvent {
            CalendarEvent(id: id, title: title, start: at(d, h, m), end: at(d, h, m).addingTimeInterval(Double(minutes) * 60),
                          isAllDay: false, location: nil, meetLink: meet ? URL(string: "https://meet.google.com/abc-defg-hij") : nil,
                          htmlLink: URL(string: "https://calendar.google.com/"), attendees: people)
        }
        return [
            e("1", "Gitwork stand-up", 0, 9, 30, minutes: 15, people: 6),
            e("2", "Fairway weekly check-in", 0, 11, 0, minutes: 45),
            e("3", "Gitwork stand-up", 1, 9, 30, minutes: 15, people: 6),
            e("4", "Northwind x Gitwork", 1, 14, 30, minutes: 60, people: 3),
            e("5", "Gitwork stand-up", 2, 9, 30, minutes: 15, people: 6),
            e("6", "PollenIQ demo", 2, 13, 0, minutes: 30),
            e("7", "Focus: proposals", 2, 15, 0, minutes: 90, people: 0, meet: false),
            e("8", "Gitwork stand-up", 3, 9, 30, minutes: 15, people: 6),
            e("9", "Acme Health handover", 3, 16, 0, minutes: 60, people: 4),
            e("10", "Gitwork stand-up", 4, 9, 30, minutes: 15, people: 6),
            e("11", "Leisure Tech retro", 4, 12, 0, minutes: 45, people: 5),
            CalendarEvent(id: "12", title: "Team day out", start: week[min(5, week.count - 1)], end: cal.date(byAdding: .day, value: 1, to: week[min(5, week.count - 1)])!,
                          isAllDay: true, location: "Manchester", meetLink: nil, htmlLink: nil, attendees: 8),
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
