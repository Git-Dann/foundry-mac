import SwiftUI

/// The detail pane: the promise, where it came from (with the quote it was read from), and the
/// few things you can do with it.
struct CommitmentDetail: View {
    @Environment(AppModel.self) private var model
    let id: String

    @State private var title = ""
    @State private var notes = ""
    @State private var counterpart = ""
    @State private var hasDue = false
    @State private var due = Date()
    @State private var loaded = false
    @State private var confirmDelete = false
    @FocusState private var focus: Field?

    enum Field { case title, notes, counterpart }

    var body: some View {
        if let c = model.store.commitment(id: id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header(c)
                    if c.source != .manual { evidence(c) }
                    details(c)
                    if !c.isBoardTask && c.state != .suggested { PlanningFields(id: id) }
                    if !c.isBoardTask {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes").font(.headline)
                            NotesEditor(markdown: $notes, onCommit: save)
                                .frame(minHeight: 180)
                        }
                    }
                    actions(c)
                }
                .padding(28)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { load(c) }
            .onChange(of: focus) { old, _ in if old != nil { save() } }
            .onDisappear { save() }
            .confirmationDialog("Delete this to-do?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    model.store.delete(id)
                    model.selectedCommitmentId = nil
                }
            } message: {
                Text("It was added by you, so it can be deleted. This can't be undone.")
            }
        }
    }

    // MARK: Sections

    private func header(_ c: Commitment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if c.state != .open || c.isSnoozed(at: Date()) || (c.dueAt.map { $0 < Date() } ?? false) {
                    StatePill(commitment: c)
                }
                if c.isLocalOnly {
                    Label("Not sent yet", systemImage: "icloud.and.arrow.up").font(.caption).foregroundStyle(.secondary)
                }
            }
            TextField("To-do", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .focused($focus, equals: .title)
                .onSubmit { save() }
                .disabled(c.state == .dismissed || c.isBoardTask)
        }
    }

    private func evidence(_ c: Commitment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(c.isBoardTask ? "On the Foundry board" : "Where this came from").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if let quote = c.quote, !quote.isEmpty {
                QuoteView(quote: quote)
            }
            if let reason = c.reason, !reason.isEmpty {
                Text(reason).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                EvidenceLabel(commitment: c).font(.callout)
                Spacer()
                if let link = c.evidenceLink {
                    Button(c.isBoardTask ? "Open on Board" : "Open \(c.source.label)") { NSWorkspace.shared.open(link) }
                        .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func details(_ c: Commitment) -> some View {
        Form {
            LabeledContent("Deadline") {
                HStack {
                    Toggle("Due date", isOn: $hasDue).labelsHidden()
                        .onChange(of: hasDue) { _, on in
                            guard loaded else { return }
                            if on, c.dueAt == nil {
                                due = Calendar.current.date(bySettingHour: DueDateParser.defaultHour, minute: 0, second: 0, of: Date()) ?? Date()
                            }
                            model.store.update(id, CommitmentPatch(dueAt: on ? .set(due) : .clear))
                        }
                    if hasDue {
                        DatePicker("", selection: $due, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .onChange(of: due) { _, new in
                                guard loaded, hasDue, new != c.dueAt else { return }
                                model.store.update(id, CommitmentPatch(dueAt: .set(new)))
                            }
                    } else {
                        Text("No date").foregroundStyle(.secondary)
                    }
                }
            }
            if let snoozed = c.snoozedUntil, c.isSnoozed(at: Date()) {
                LabeledContent("Snoozed until") {
                    HStack {
                        Text(snoozed.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                        Button("Wake up") { model.store.unsnooze(id) }.controlSize(.small)
                    }
                }
            }
            if !c.isBoardTask {
                TextField("For", text: $counterpart, prompt: Text("Who it's for"))
                    .focused($focus, equals: .counterpart)
                    .onSubmit { save() }
            }
        }
        .formStyle(.columns)
        .disabled(c.state == .dismissed)
    }

    @ViewBuilder private func actions(_ c: Commitment) -> some View {
        HStack(spacing: 10) {
            switch c.state {
            case .suggested:
                Button("Add to my to-dos") { model.store.accept(id) }
                    .buttonStyle(.glassProminent)
                Button("Not mine") { model.store.dismiss(id) }.buttonStyle(.glass)
            case .open:
                Button("Mark done") { model.complete(id) }
                    .buttonStyle(.glassProminent)
                Button("Focus", systemImage: "timer") {
                    FocusSession.shared.start(todoId: id, todoTitle: c.title)
                    model.selection = .focus
                }
                .buttonStyle(.glass)
                if !c.isBoardTask {
                    Menu("Snooze") {
                        ForEach(SnoozeOption.allCases) { o in
                            Button(o.title) { model.store.snooze(id, until: o.until(from: Date())) }
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.glass)
                    .fixedSize()
                    Button("Dismiss") { model.store.dismiss(id) }.buttonStyle(.glass)
                }
            case .done, .dismissed:
                Button("Reopen") { model.store.reopen(id) }.buttonStyle(.glass)
            }
            Spacer()
            if c.source == .manual {
                Button("Delete…", role: .destructive) { confirmDelete = true }
                    .buttonStyle(.borderless)
            }
        }
        .controlSize(.large)
    }

    // MARK: Editing

    private func load(_ c: Commitment) {
        title = c.title
        notes = c.notes ?? ""
        counterpart = c.counterpart ?? ""
        hasDue = c.dueAt != nil
        due = c.dueAt ?? Date()
        DispatchQueue.main.async { loaded = true }
    }

    private func save() {
        guard loaded, let c = model.store.commitment(id: id), !c.isBoardTask else { return }
        var patch = CommitmentPatch()
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, t != c.title { patch.title = .set(String(t.prefix(200))) }
        let n = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if n != (c.notes ?? "") { patch.notes = n.isEmpty ? .clear : .set(String(n.prefix(4000))) }
        let who = counterpart.trimmingCharacters(in: .whitespacesAndNewlines)
        if who != (c.counterpart ?? "") { patch.counterpart = who.isEmpty ? .clear : .set(String(who.prefix(120))) }
        model.store.update(id, patch)
    }
}

struct StatePill: View {
    let commitment: Commitment

    var body: some View {
        let (text, color): (String, Color) = switch commitment.state {
        case .suggested: ("Suggested", .accentColor)
        case .open: commitment.isSnoozed(at: Date()) ? ("Snoozed", .secondary) : ((commitment.dueAt.map { $0 < Date() } ?? false) ? ("Overdue", .red) : ("Open", .secondary))
        case .done: ("Done", .green)
        case .dismissed: ("Dismissed", .secondary)
        }
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}
