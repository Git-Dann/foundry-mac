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

            VStack(alignment: .leading, spacing: 2) {
                Text(commitment.title)
                    .lineLimit(compact ? 2 : 3)
                    .strikethrough(commitment.state == .done, color: .secondary)
                    .foregroundStyle(commitment.state == .done ? .secondary : .primary)
                meta
            }
            Spacer(minLength: 4)
            if hovering && commitment.state == .open && !commitment.isBoardTask {
                SnoozeMenu(id: commitment.id)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, compact ? 3 : 4)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .contextMenu { CommitmentContextMenu(commitment: commitment) }
    }

    @ViewBuilder private var meta: some View {
        let parts = metaParts
        if !parts.isEmpty {
            HStack(spacing: 6) {
                if let due = commitment.dueAt, commitment.state == .open {
                    Text(DueText.string(due))
                        .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                }
                if commitment.isBoardTask, let client = commitment.counterpart, !client.isEmpty {
                    BoardTag(client: client)
                } else if let counterpart = commitment.counterpart, !counterpart.isEmpty {
                    Text(counterpart).foregroundStyle(.secondary)
                }
                if commitment.source != .manual && !commitment.isBoardTask {
                    Label(commitment.source.label, systemImage: commitment.source.symbol)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.tertiary)
                        .help("From \(commitment.source.label.lowercased())")
                }
                if commitment.isLocalOnly || model.store.outbox.contains(where: { $0.targetId == commitment.id }) {
                    Image(systemName: "icloud.and.arrow.up")
                        .foregroundStyle(.tertiary)
                        .help("Waiting to be sent to Foundry")
                }
            }
            .font(.caption)
            .lineLimit(1)
        }
    }

    private var metaParts: [String] {
        var p: [String] = []
        if commitment.dueAt != nil && commitment.state == .open { p.append("due") }
        if commitment.counterpart?.isEmpty == false { p.append("who") }
        if commitment.source != .manual { p.append("src") }
        if commitment.isLocalOnly || model.store.outbox.contains(where: { $0.targetId == commitment.id }) { p.append("pending") }
        return p
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

/// A suggestion: what was found, the words it was read from, and where. Nothing joins the list
/// until the person says so.
struct SuggestionRow: View {
    @Environment(AppModel.self) private var model
    let commitment: Commitment
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(commitment.title)
                .fontWeight(.medium)
                .lineLimit(compact ? 2 : 4)
            if let quote = commitment.quote, !quote.isEmpty {
                QuoteView(quote: quote, lineLimit: compact ? 3 : nil)
            }
            HStack(spacing: 8) {
                EvidenceLabel(commitment: commitment)
                Spacer(minLength: 6)
                Button("Not mine") { model.store.dismiss(commitment.id) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Button("Add") { model.store.accept(commitment.id) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .font(.caption)
        }
        .padding(.vertical, 6)
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

/// "FELLAS" on a board task, so it reads as client work at a glance.
struct BoardTag: View {
    let client: String

    var body: some View {
        Text(client.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.4)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
            .help("A task on \(client)'s Foundry board")
    }
}

/// "3 suggested from Foundry · Review". Suggestions wait behind this rather than filling the
/// list: nothing joins your to-dos until you add it.
struct SuggestionsCard: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        let review = CommitmentGrouping.suggestions(model.store.items)
        if !review.isEmpty {
            Button { open = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(.tint)
                    Text(review.count == 1 ? "1 suggested from Foundry" : "\(review.count) suggested from Foundry")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("Review").foregroundStyle(.tint)
                }
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $open, arrowEdge: .bottom) {
                SuggestionsReview(onDone: { open = false })
            }
        }
    }
}

struct SuggestionsReview: View {
    @Environment(AppModel.self) private var model
    var onDone: () -> Void

    var body: some View {
        let review = CommitmentGrouping.suggestions(model.store.items)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Suggested from Foundry").font(.headline)
                Spacer()
                if review.count > 1 {
                    Button("Not mine, all") {
                        for c in review { model.store.dismiss(c.id) }
                        onDone()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            Text("Read from your meetings, email and Slack. Nothing is added until you say so.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(review) { c in
                        SuggestionRow(commitment: c, compact: true).padding(.horizontal, 14)
                        Divider().padding(.leading, 14)
                    }
                    if review.isEmpty {
                        Text("All reviewed.").foregroundStyle(.secondary).padding(20)
                    }
                }
            }
            .frame(maxHeight: 420)
        }
        .frame(width: 380)
        .onChange(of: review.isEmpty) { _, empty in if empty { onDone() } }
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
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(.secondary)
                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit {
                        if model.store.add(text: text) != nil { text = "" }
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            if focused && !text.isEmpty {
                DueHint(text: text).font(.caption).padding(.leading, 10)
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
