import SwiftUI

/// How a due date reads in a row: "Overdue · Tue", "Today 17:00", "Fri 21 Nov".
enum DueText {
    static func string(_ due: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = due.formatted(.dateTime.hour().minute())
        if due < now {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: due), to: calendar.startOfDay(for: now)).day ?? 0
            switch days {
            case 0: return "Overdue · \(time)"
            case 1: return "Overdue · yesterday"
            case 2..<7: return "Overdue · \(due.formatted(.dateTime.weekday(.wide)))"
            default: return "Overdue · \(due.formatted(.dateTime.day().month(.abbreviated)))"
            }
        }
        if calendar.isDateInToday(due) { return "Today \(time)" }
        if calendar.isDateInTomorrow(due) { return "Tomorrow" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        if days < 7 { return due.formatted(.dateTime.weekday(.wide)) }
        return due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

/// The round tick used to complete. Big enough to hit, quiet until hovered.
struct CompleteButton: View {
    var done: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: done ? "checkmark.circle.fill" : (hovering ? "checkmark.circle" : "circle"))
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(done ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(done ? "Mark as not done" : "Mark done")
        .accessibilityLabel(done ? "Mark as not done" : "Mark done")
    }
}

/// One open (or done) commitment.
struct CommitmentRow: View {
    @Environment(AppModel.self) private var model
    let commitment: Commitment
    var compact = false
    @State private var hovering = false

    private var isOverdue: Bool { (commitment.dueAt.map { $0 < Date() } ?? false) && commitment.state == .open }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            CompleteButton(done: commitment.state == .done) {
                if commitment.state == .done { model.store.reopen(commitment.id) } else { model.complete(commitment.id) }
            }
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }

            VStack(alignment: .leading, spacing: 3) {
                Text(Display.lines(for: commitment).title)
                    .lineLimit(compact ? 2 : 3)
                    .strikethrough(commitment.state == .done, color: .secondary)
                    .foregroundStyle(commitment.state == .done ? .secondary : .primary)
                HStack(spacing: 6) {
                    RowMeta(commitment: commitment, subtitle: Display.lines(for: commitment).subtitle)
                    if commitment.isLocalOnly || model.store.outbox.contains(where: { $0.targetId == commitment.id }) {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .help("Waiting to be sent to Foundry")
                    }
                }
            }
            Spacer(minLength: 4)
            if hovering && commitment.state == .open && !commitment.isBoardTask {
                SnoozeMenu(id: commitment.id)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, compact ? 6 : 8)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .contextMenu { CommitmentContextMenu(commitment: commitment) }
    }
}

struct SnoozeMenu: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        Menu {
            ForEach(SnoozeOption.allCases) { option in
                Button(option.title) { model.store.snooze(id, until: option.until(from: Date())) }
            }
        } label: {
            Image(systemName: "moon.zzz")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Snooze")
        .accessibilityLabel("Snooze")
    }
}

struct CommitmentContextMenu: View {
    @Environment(AppModel.self) private var model
    let commitment: Commitment

    var body: some View {
        switch commitment.state {
        case .open:
            Button("Mark Done") { model.complete(commitment.id) }
            if !commitment.isBoardTask {
                Menu("Snooze") {
                    ForEach(SnoozeOption.allCases) { o in
                        Button(o.title) { model.store.snooze(commitment.id, until: o.until(from: Date())) }
                    }
                }
            }
            if commitment.isSnoozed(at: Date()) {
                Button("Wake Up") { model.store.unsnooze(commitment.id) }
            }
        case .suggested:
            Button("Add to My To-dos") { model.store.accept(commitment.id) }
        case .done, .dismissed:
            Button("Reopen") { model.store.reopen(commitment.id) }
        }
        Divider()
        Button("Open in Window") { model.showInWindow(id: commitment.id) }
        if let link = commitment.evidenceLink {
            Button(commitment.isBoardTask ? "Open on Board" : "Open \(commitment.source.label)") { NSWorkspace.shared.open(link) }
        }
        if commitment.state != .dismissed && !commitment.isBoardTask {
            Divider()
            Button(commitment.state == .suggested ? "Not Mine" : "Dismiss") { model.store.dismiss(commitment.id) }
        }
    }
}

/// A suggestion, as an ordinary list row: what it is, where it came from, and two system
/// buttons. Swipe right to add, left for "Not mine". Nothing joins the list until you say so.
struct SuggestionRow: View {
    @Environment(AppModel.self) private var model
    let commitment: Commitment
    var compact = false

    var body: some View {
        let lines = Display.lines(for: commitment)
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: commitment.source.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(lines.title).lineLimit(compact ? 1 : 2)
                Text(lines.subtitle ?? [commitment.source.label, commitment.evidenceLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button("Not Mine", systemImage: "xmark") { withAnimation { model.store.dismiss(commitment.id) } }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .help("Not mine")
            Button("Add") { withAnimation { model.store.accept(commitment.id) } }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .leading) {
            Button("Add", systemImage: "plus") { model.store.accept(commitment.id) }.tint(.accentColor)
        }
        .swipeActions(edge: .trailing) {
            Button("Not Mine", systemImage: "xmark") { model.store.dismiss(commitment.id) }
        }
        .contextMenu { CommitmentContextMenu(commitment: commitment) }
    }
}

struct QuoteView: View {
    let quote: String
    var lineLimit: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1).fill(.quaternary).frame(width: 2)
            Text("“\(quote)”")
                .font(.callout)
                .italic()
                .foregroundStyle(.secondary)
                .lineLimit(lineLimit)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "Email · Re: Kick-off · 2 Nov ↗". The link opens the original email, message or meeting.
struct EvidenceLabel: View {
    let commitment: Commitment

    var body: some View {
        let text = [commitment.source.label, commitment.evidenceLabel, commitment.evidenceAt?.formatted(.dateTime.day().month(.abbreviated))]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        if let link = commitment.evidenceLink {
            Link(destination: link) {
                Label(text, systemImage: commitment.source.symbol).lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .help("Open the original")
        } else {
            Label(text, systemImage: commitment.source.symbol)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
    }
}


/// The header of the suggestions Section: what they are, and clearing them all.
struct SuggestionsHeader: View {
    @Environment(AppModel.self) private var model
    let count: Int

    var body: some View {
        HStack {
            Label("Suggested · \(count)", systemImage: "sparkles")
            Spacer()
            if count > 1 {
                Button("Not Mine, All") {
                    withAnimation { for c in CommitmentGrouping.suggestions(model.store.items) { model.store.dismiss(c.id) } }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
    }
}

/// One quiet line when a source couldn't be read. It doesn't push your to-dos down the page.
struct SourceFootnote: View {
    @Environment(\.openSettings) private var openSettings
    let text: String

    var body: some View {
        Button { openSettings() } label: {
            Label(text, systemImage: "exclamationmark.circle")
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
        .help(text + " Click to see your sources.")
    }
}

/// The quick-add line used in the menu bar and the window.
struct QuickAddField: View {
    @Environment(AppModel.self) private var model
    var prompt = "Add a to-do"
    var focusToken: Int = 0
    /// Where it was typed: a list, Today, Someday… (words in the line still win).
    var defaults: NewCommitment? = nil
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .foregroundStyle(focused ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { if model.store.add(text: text, defaults: defaults) != nil { text = "" } }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular.interactive(), in: .capsule)
            if focused && !text.isEmpty {
                DueHint(text: text).font(.caption).padding(.leading, 4)
            }
        }
        .onChange(of: focusToken) { focused = true }
    }
}

/// "Done · Send Acme the deck   Undo". Disappears after a few seconds.
struct UndoBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let c = model.lastCompleted {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                Text("Done: \(c.title)").lineLimit(1).foregroundStyle(.secondary)
                Spacer()
                Button("Undo") { model.undoComplete() }
                    .buttonStyle(.borderless)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            .task(id: c.id) {
                try? await Task.sleep(for: .seconds(6))
                if model.lastCompleted?.id == c.id { withAnimation { model.lastCompleted = nil } }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// The empty state: calm, one line, no illustration.
struct QuietEmpty: View {
    let title: String
    var detail: String?
    var symbol = "checkmark.circle"

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let detail { Text(detail) }
        }
    }
}
