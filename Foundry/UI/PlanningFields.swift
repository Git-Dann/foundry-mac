import SwiftUI

/// The planning half of the detail pane: list, when, deadline-adjacent reminder, repeat, priority,
/// tags and the checklist. Every control is a native one, bound straight to the store, so each
/// change is saved (and queued offline) as it's made.
struct PlanningFields: View {
    @Environment(AppModel.self) private var model
    let id: String
    @State private var tagText = ""
    @State private var newItem = ""
    @FocusState private var addingItem: Bool

    private var c: Commitment? { model.store.commitment(id: id) }

    private func binding<V>(_ get: @escaping (Commitment) -> V, _ patch: @escaping (V) -> CommitmentPatch) -> Binding<V> where V: Equatable {
        Binding(
            get: { c.map(get)! },
            set: { new in if let cur = c, get(cur) != new { model.store.update(id, patch(new)) } }
        )
    }

    var body: some View {
        if let c {
            Form {
                Section("Plan") {
                    Picker("List", selection: binding({ $0.listId }, { CommitmentPatch(listId: $0.map { .set($0) } ?? .clear) })) {
                        Label("Inbox", systemImage: "tray").tag(String?.none)
                        ForEach(model.store.lists) { l in
                            Label(l.name, systemImage: l.icon).tag(String?.some(l.id))
                        }
                    }
                    LabeledContent("When") {
                        HStack(spacing: 8) {
                            Picker("When", selection: whenChoice(c)) {
                                Text("Not set").tag(WhenChoice.none)
                                Text("Today").tag(WhenChoice.today)
                                Text("This Evening").tag(WhenChoice.evening)
                                Text("Tomorrow").tag(WhenChoice.tomorrow)
                                Text("On a day…").tag(WhenChoice.day)
                                Text("Someday").tag(WhenChoice.someday)
                            }
                            .labelsHidden()
                            .fixedSize()
                            if !c.someday, let start = c.startAt {
                                DatePicker("Day", selection: binding({ $0.startAt ?? start }, { CommitmentPatch(startAt: .set($0)) }), displayedComponents: .date)
                                    .labelsHidden()
                            }
                        }
                    }
                    OptionalDateRow(title: "Reminder", date: c.remindAt, defaultDate: defaultReminder(c)) {
                        model.store.update(id, CommitmentPatch(remindAt: $0.map { .set($0) } ?? .clear))
                    }
                    Picker("Repeat", selection: binding({ $0.recurrence }, { CommitmentPatch(recurrence: $0.map { .set($0) } ?? .clear) })) {
                        Text("Never").tag(String?.none)
                        ForEach(Recurrence.presets, id: \.rule) { Text($0.title).tag(String?.some($0.rule)) }
                        if let custom = c.recurrence, Recurrence(rule: custom).map({ !Recurrence.presets.contains($0) }) ?? false {
                            Text(Recurrence(rule: custom)!.title).tag(String?.some(custom))
                        }
                    }
                    Picker("Priority", selection: binding({ $0.priority }, { CommitmentPatch(priority: $0) })) {
                        ForEach(Priority.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    TextField("Tags", text: $tagText, prompt: Text("sales, q4"))
                        .onSubmit(saveTags)
                }
                Section {
                    ForEach(c.checklist) { item in
                        HStack {
                            Toggle(isOn: Binding(
                                get: { item.done },
                                set: { done in setChecklist(c.checklist.map { $0.id == item.id ? ChecklistItem(id: $0.id, text: $0.text, done: done) : $0 }) }
                            )) {
                                Text(item.text).strikethrough(item.done, color: .secondary).foregroundStyle(item.done ? .secondary : .primary)
                            }
                            .toggleStyle(.checkbox)
                            Spacer()
                            Button("Remove", systemImage: "minus.circle") { setChecklist(c.checklist.filter { $0.id != item.id }) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onMove { from, to in
                        var list = c.checklist
                        list.move(fromOffsets: from, toOffset: to)
                        setChecklist(list)
                    }
                    TextField("Add an item", text: $newItem)
                        .focused($addingItem)
                        .onSubmit {
                            let t = newItem.trimmingCharacters(in: .whitespaces)
                            guard !t.isEmpty else { return }
                            setChecklist(c.checklist + [ChecklistItem(text: String(t.prefix(200)))])
                            newItem = ""
                            addingItem = true
                        }
                } header: {
                    let done = c.checklist.filter(\.done).count
                    HStack {
                        Text("Checklist")
                        if !c.checklist.isEmpty {
                            Spacer()
                            Gauge(value: Double(done), in: 0...Double(c.checklist.count)) { EmptyView() }
                                .gaugeStyle(.accessoryLinearCapacity)
                                .frame(width: 60)
                            Text("\(done)/\(c.checklist.count)").monospacedDigit()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .disabled(!model.store.supportsPlanning)
            .overlay(alignment: .top) {
                if !model.store.supportsPlanning {
                    Label("Lists, tags, repeats and checklists turn on when Foundry is updated.", systemImage: "clock.arrow.circlepath")
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.top, 8)
                }
            }
            .onAppear { tagText = c.tags.joined(separator: ", ") }
            .onChange(of: c.tags) { _, new in tagText = new.joined(separator: ", ") }
        }
    }

    // MARK: When

    enum WhenChoice: Hashable { case none, today, evening, tomorrow, day, someday }

    private func whenChoice(_ c: Commitment) -> Binding<WhenChoice> {
        Binding(
            get: {
                if c.someday { return .someday }
                guard let s = c.startAt else { return .none }
                let cal = Calendar.current
                if cal.isDateInToday(s) || s < Date() { return c.evening ? .evening : .today }
                if cal.isDateInTomorrow(s) { return .tomorrow }
                return .day
            },
            set: { choice in
                let cal = Calendar.current
                let today = cal.startOfDay(for: Date())
                let patch: CommitmentPatch
                switch choice {
                case .none: patch = CommitmentPatch(startAt: .clear, evening: false, someday: false)
                case .today: patch = CommitmentPatch(startAt: .set(today), evening: false)
                case .evening: patch = CommitmentPatch(startAt: .set(today), evening: true)
                case .tomorrow: patch = CommitmentPatch(startAt: .set(cal.date(byAdding: .day, value: 1, to: today)!), evening: false)
                case .day: patch = CommitmentPatch(startAt: .set(c.startAt ?? cal.date(byAdding: .day, value: 2, to: today)!), evening: false)
                case .someday: patch = CommitmentPatch(someday: true)
                }
                withAnimation(.smooth) { model.store.update(id, patch) }
            }
        )
    }

    private func defaultReminder(_ c: Commitment) -> Date {
        let cal = Calendar.current
        let base = c.startAt ?? c.dueAt ?? Date()
        let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: base)!
        return nine > Date() ? nine : Date().addingTimeInterval(3600)
    }

    private func saveTags() {
        let tags = tagText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "#", with: "") }
            .filter { !$0.isEmpty }
        let unique = Array(NSOrderedSet(array: tags)) as? [String] ?? tags
        if unique != c?.tags { model.store.update(id, CommitmentPatch(tags: Array(unique.prefix(20)))) }
    }

    private func setChecklist(_ items: [ChecklistItem]) {
        model.store.update(id, CommitmentPatch(checklist: items))
    }
}

/// A date that may not be set: a switch, then the picker.
struct OptionalDateRow: View {
    let title: String
    let date: Date?
    let defaultDate: Date
    let onChange: (Date?) -> Void

    var body: some View {
        LabeledContent(title) {
            HStack {
                Toggle(title, isOn: Binding(get: { date != nil }, set: { onChange($0 ? defaultDate : nil) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                if let date {
                    DatePicker(title, selection: Binding(get: { date }, set: { onChange($0) }), displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
            }
        }
    }
}
