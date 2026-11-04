import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        Group {
            if !model.auth.isSignedIn {
                SignInPrompt()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
            } else if let wide = WideScreen(model.selection) {
                // Views that want the whole width replace the list and detail columns.
                NavigationSplitView(columnVisibility: $columns) {
                    Sidebar().navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
                } detail: {
                    wide.view
                }
            } else {
                NavigationSplitView(columnVisibility: $columns) {
                    Sidebar().navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
                } content: {
                    TodoListView().navigationSplitViewColumnWidth(min: 360, ideal: 440)
                } detail: {
                    if let id = model.selectedCommitmentId, model.store.commitment(id: id) != nil {
                        CommitmentDetail(id: id).id(id)
                    } else if model.selectedIds.count > 1 {
                        BatchSummary(ids: model.selectedIds)
                    } else {
                        ContentUnavailableView("No To-do Selected", systemImage: "checklist", description: Text("Pick one to see its details, or select several to change them together."))
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .buttonBorderShape(.capsule)
        .onAppear {
            model.openWindowAction = { openWindow(id: "main") }
            model.refreshIfStale()
        }
    }
}

/// Destinations that take the full width instead of list + detail.
struct WideScreen {
    let view: AnyView
    @MainActor init?(_ item: SidebarItem) {
        switch item {
        case .calendar: view = AnyView(CalendarScreen())
        case .foundry: view = AnyView(FeedView())
        case .board: view = AnyView(KanbanView().navigationTitle("Board"))
        case .matrix: view = AnyView(MatrixView().navigationTitle("Priorities"))
        default: return nil
        }
    }
}

// MARK: Sidebar

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @State private var editingList: TodoList?
    @State private var creatingList = false
    @State private var editingSmart: TodoFilter?

    private var selection: Binding<String?> {
        Binding(
            get: {
                if model.selection == .filtered, let f = model.filter { return "f:" + f.id }
                return "s:" + model.selection.rawValue
            },
            set: { token in
                guard let token else { return }
                if token.hasPrefix("s:"), let item = SidebarItem(rawValue: String(token.dropFirst(2))) {
                    model.selection = item
                } else if token.hasPrefix("f:") {
                    let id = String(token.dropFirst(2))
                    if id.hasPrefix("list:") { model.show(filter: .list(String(id.dropFirst(5)))) }
                    else if id.hasPrefix("tag:") { model.show(filter: .tag(String(id.dropFirst(4)))) }
                    else if let smart = model.smartLists.first(where: { $0.id == id }) { model.show(filter: smart) }
                }
                model.selectedIds = []
            }
        )
    }

    var body: some View {
        let now = Date()
        let items = model.store.items
        List(selection: selection) {
            Section {
                ForEach(SidebarItem.planning) { item in
                    Label { Text(item.title) } icon: { Image(systemName: item.symbol).foregroundStyle(item.tint) }
                        .badge(count(item, items: items, now: now))
                        .tag("s:" + item.rawValue)
                }
            }
            Section("Views") {
                ForEach(SidebarItem.views) { item in
                    Label(item.title, systemImage: item.symbol)
                        .badge(item == .foundry ? model.feed.mentionCount : 0)
                        .tag("s:" + item.rawValue)
                }
            }
            Section("Lists") {
                ForEach(model.store.lists) { list in
                    Label { Text(list.name) } icon: { Image(systemName: list.icon).foregroundStyle(list.tint) }
                        .badge(items.filter { $0.state == .open && $0.listId == list.id }.count)
                        .tag("f:list:" + list.id)
                        .contextMenu {
                            Button("Edit List…") { editingList = list }
                            Button("Delete List", role: .destructive) { Task { await model.store.deleteList(list.id) } }
                        }
                        .dropDestination(for: String.self) { ids, _ in
                            for id in ids { model.store.update(id, CommitmentPatch(listId: .set(list.id))) }
                            return !ids.isEmpty
                        }
                }
                Button { creatingList = true } label: { Label("New List", systemImage: "plus") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            let tags = Plan.tags(items)
            if !tags.isEmpty {
                Section("Tags") {
                    ForEach(tags.prefix(12), id: \.tag) { t in
                        Label("#" + t.tag, systemImage: "number").badge(t.count).tag("f:tag:" + t.tag)
                    }
                }
            }
            Section("Smart Lists") {
                ForEach(model.smartLists) { f in
                    Label(f.name, systemImage: f.symbol)
                        .badge(items.filter { f.matches($0, now: now) }.count)
                        .tag("f:" + f.id)
                        .contextMenu {
                            Button("Edit…") { editingSmart = f }
                            Button("Delete", role: .destructive) { model.smartLists.removeAll { $0.id == f.id } }
                        }
                }
                Button { editingSmart = TodoFilter(name: "") } label: { Label("New Smart List", systemImage: "plus") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                if model.store.isOffline || !model.network.isOnline {
                    Label(model.store.pendingCount > 0 ? "Offline · \(model.store.pendingCount) to send" : "Offline", systemImage: "wifi.slash")
                }
                Button { model.openFoundryWeb() } label: { Label("Open Foundry", systemImage: "arrow.up.right.square") }
                    .buttonStyle(.borderless)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .sheet(isPresented: $creatingList) { ListEditor(list: nil) }
        .sheet(item: $editingList) { ListEditor(list: $0) }
        .sheet(item: $editingSmart) { SmartListEditor(filter: $0) }
    }

    private func count(_ item: SidebarItem, items: [Commitment], now: Date) -> Int {
        switch item {
        case .inbox: Plan.inbox(items, now: now).count
        case .today: items.filter { Plan.isToday($0, now: now) }.count
        default: 0
        }
    }
}

// MARK: The list

struct TodoListView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model
        let now = Date()
        let items = matching(model.store.items)
        let sections = sections(items, now: now)
        let canReorder = search.isEmpty && [.inbox, .today, .anytime, .someday, .filtered].contains(model.selection)
        List(selection: $model.selectedIds) {
            if model.selection != .done {
                QuickAddField(prompt: quickAddPrompt, focusToken: model.focusQuickAddToken, defaults: addDefaults)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 6)
                UndoBar().listRowSeparator(.hidden)
            }
            if model.selection == .today {
                let review = CommitmentGrouping.suggestions(items)
                if !review.isEmpty {
                    Section {
                        ForEach(review) { SuggestionRow(commitment: $0).tag($0.id) }
                    } header: {
                        SuggestionsHeader(count: review.count)
                    }
                }
            }
            if model.selection == .done {
                Section {
                    ForEach(CommitmentGrouping.done(items)) { CommitmentRow(commitment: $0).tag($0.id) }
                }
            }
            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { c in
                        CommitmentRow(commitment: c).tag(c.id).draggable(c.id)
                    }
                    .onMove(perform: canReorder ? { from, to in move(section.items, from: from, to: to) } : nil)
                } header: {
                    if !section.title.isEmpty {
                        Text(section.title).foregroundStyle(section.isAlert ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    }
                }
            }
        }
        .listStyle(.inset)
        .contentMargins(.vertical, 8, for: .scrollContent)
        .contextMenu(forSelectionType: String.self) { ids in
            if !ids.isEmpty { BatchMenuItems(ids: ids) }
        }
        .overlay {
            if sections.isEmpty && model.selection != .done && !(model.selection == .today && !CommitmentGrouping.suggestions(items).isEmpty) {
                ContentUnavailableView(emptyTitle, systemImage: emptySymbol, description: Text(emptyDetail))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let notes = [model.store.boardProblem, SourceProblem.summary(model.store.settings.sourceStatus)].compactMap { $0 }
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(notes, id: \.self) { SourceFootnote(text: $0) }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search")
        .searchFocused($searchFocused)
        .onChange(of: model.focusSearchToken) { searchFocused = true }
        .onKeyPress(.space) {
            guard let id = model.selectedCommitmentId, let c = model.store.commitment(id: id) else { return .ignored }
            switch c.state {
            case .open: model.complete(id)
            case .suggested: model.store.accept(id)
            case .done, .dismissed: model.store.reopen(id)
            }
            return .handled
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle(now: now))
        .toolbar {
            if model.selectedIds.count > 1 {
                ToolbarItem {
                    Menu {
                        BatchMenuItems(ids: model.selectedIds)
                    } label: {
                        Label("\(model.selectedIds.count) Selected", systemImage: "checklist.checked")
                    }
                }
            }
            ToolbarItem {
                Button { Task { await model.store.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.store.isRefreshing)
            }
        }
    }

    // MARK: Content per destination

    private func sections(_ items: [Commitment], now: Date) -> [Plan.Section] {
        switch model.selection {
        case .inbox: [Plan.Section(id: "inbox", title: "", items: Plan.inbox(items, now: now))].filter { !$0.items.isEmpty }
        case .today: Plan.today(items, now: now)
        case .upcoming: Plan.upcoming(items, now: now)
        case .anytime: Plan.anytime(items, lists: model.store.lists, now: now)
        case .someday: Plan.someday(items, lists: model.store.lists, now: now)
        case .filtered: model.filter.map { Plan.filtered(items, filter: $0, lists: model.store.lists, now: now) } ?? []
        default: []
        }
    }

    private var addDefaults: NewCommitment {
        var d = NewCommitment(title: "")
        switch model.selection {
        case .today: d.startAt = Calendar.current.startOfDay(for: Date())
        case .someday: d.someday = true
        case .filtered:
            d.listId = model.filter?.listId
            d.tags = model.filter?.tags ?? []
        default: break
        }
        return d
    }

    private var quickAddPrompt: String {
        switch model.selection {
        case .today: "Add to Today. Try “Call Valu 3pm #sales !!”"
        case .someday: "Add to Someday"
        case .filtered: model.filter?.listId.flatMap { model.store.list(id: $0)?.name }.map { "Add to \($0)" } ?? "Add a to-do"
        default: "Add a to-do. Try “Send Acme the deck fri”"
        }
    }

    private var title: String {
        if model.selection == .filtered, let f = model.filter {
            if let id = f.listId, let l = model.store.list(id: id) { return l.name }
            if f.tags.count == 1, f.name.isEmpty { return "#" + f.tags[0] }
            return f.name.isEmpty ? "Filter" : f.name
        }
        return model.selection.title
    }

    private func subtitle(now: Date) -> String {
        if let e = model.store.lastError { return e }
        switch model.selection {
        case .today:
            let n = model.store.items.filter { Plan.isToday($0, now: now) }.count
            return n == 0 ? "Nothing planned" : "\(n) to do today"
        case .inbox: return "Unsorted. Give each one a list or a day."
        case .upcoming: return "Planned and due, by day"
        case .anytime: return "Everything you could pick up now"
        case .someday: return "Not now, but not forgotten"
        case .done: return "Finished in the last two weeks"
        default: return ""
        }
    }

    private var emptyTitle: String {
        switch model.selection {
        case .inbox: "Inbox Zero"
        case .today: "Nothing Planned for Today"
        case .upcoming: "Nothing Coming Up"
        case .someday: "Nothing for Someday"
        default: "Nothing Here"
        }
    }
    private var emptySymbol: String {
        switch model.selection { case .inbox: "tray"; case .today: "star"; default: "checkmark.circle" }
    }
    private var emptyDetail: String {
        switch model.selection {
        case .inbox: "Everything has a list or a day."
        case .today: "Plan something from Anytime, or add one above."
        case .upcoming: "Give a to-do a day or a deadline and it appears here."
        default: "Add a to-do above."
        }
    }

    private func move(_ section: [Commitment], from: IndexSet, to: Int) {
        var ids = section.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        withAnimation(.smooth) { model.store.reorder(ids) }
    }

    private func matching(_ items: [Commitment]) -> [Commitment] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { c in
            ([c.title, c.notes, c.counterpart, c.quote, c.evidenceLabel].compactMap { $0?.lowercased() } + c.tags.map { "#" + $0 })
                .contains { $0.contains(q) }
        }
    }
}

// MARK: Batch edits (one or several selected)

struct BatchMenuItems: View {
    @Environment(AppModel.self) private var model
    let ids: Set<String>

    var body: some View {
        let own = ids.filter { !$0.hasPrefix(Commitment.boardPrefix) }
        let start = Calendar.current.startOfDay(for: Date())
        Button("Mark Done", systemImage: "checkmark.circle") { ids.forEach { model.complete($0) } }
        Divider()
        Button("Today", systemImage: "star") { own.forEach { model.store.update($0, CommitmentPatch(startAt: .set(start), evening: false)) } }
        Button("This Evening", systemImage: "moon") { own.forEach { model.store.update($0, CommitmentPatch(startAt: .set(start), evening: true)) } }
        Button("Tomorrow", systemImage: "sunrise") {
            let t = Calendar.current.date(byAdding: .day, value: 1, to: start)!
            own.forEach { model.store.update($0, CommitmentPatch(startAt: .set(t), evening: false)) }
        }
        Button("Someday", systemImage: "archivebox") { own.forEach { model.store.update($0, CommitmentPatch(someday: true)) } }
        Divider()
        Menu("Move to List") {
            Button("Inbox") { own.forEach { model.store.update($0, CommitmentPatch(listId: .clear)) } }
            ForEach(model.store.lists) { l in
                Button(l.name, systemImage: l.icon) { own.forEach { model.store.update($0, CommitmentPatch(listId: .set(l.id))) } }
            }
        }
        Menu("Priority") {
            ForEach(Priority.allCases) { p in
                Button(p.title) { own.forEach { model.store.update($0, CommitmentPatch(priority: p.rawValue)) } }
            }
        }
        if ids.count == 1, let id = ids.first, let c = model.store.commitment(id: id), let link = c.evidenceLink {
            Divider()
            Button(c.isBoardTask ? "Open on Board" : "Open \(c.source.label)") { NSWorkspace.shared.open(link) }
        }
        Divider()
        Button("Dismiss", systemImage: "xmark", role: .destructive) { own.forEach { model.store.dismiss($0) } }
    }
}

struct BatchSummary: View {
    let ids: Set<String>
    var body: some View {
        ContentUnavailableView {
            Label("\(ids.count) To-dos Selected", systemImage: "checklist.checked")
        } description: {
            Text("Change them together from the toolbar, or right-click.")
        } actions: {
            Menu("Change") { BatchMenuItems(ids: ids) }
                .menuStyle(.button)
                .buttonStyle(.glassProminent)
                .fixedSize()
        }
    }
}

// MARK: List and smart-list editors (native Forms in sheets)

struct ListEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let list: TodoList?
    @State private var name = ""
    @State private var color = "blue"
    @State private var symbol = "list.bullet"
    @State private var area = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Area", text: $area, prompt: Text("Optional, e.g. Clients or Personal"))
                Picker("Colour", selection: $color) {
                    ForEach(TodoList.colors, id: \.self) { c in
                        Text(c.capitalized).tag(c)
                    }
                }
                Picker("Icon", selection: $symbol) {
                    ForEach(TodoList.symbols, id: \.self) { Label($0, systemImage: $0).labelStyle(.iconOnly).tag($0) }
                }
                .pickerStyle(.palette)
            }
            .formStyle(.grouped)
            .navigationTitle(list == nil ? "New List" : "Edit List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(list == nil ? "Create" : "Save") {
                        Task {
                            let a = area.trimmingCharacters(in: .whitespaces)
                            if var l = list {
                                l.name = name; l.color = color; l.symbol = symbol; l.area = a.isEmpty ? nil : a
                                await model.store.updateList(l)
                            } else if let l = await model.store.createList(name: name, color: color, symbol: symbol, area: a.isEmpty ? nil : a) {
                                model.show(filter: .list(l.id))
                            }
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(width: 440, height: 300)
        .onAppear {
            if let list { name = list.name; color = list.color ?? "blue"; symbol = list.icon; area = list.area ?? "" }
        }
    }
}

struct SmartListEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var filter: TodoFilter
    @State private var tagText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $filter.name)
                Picker("List", selection: $filter.listId) {
                    Text("Any list").tag(String?.none)
                    ForEach(model.store.lists) { Text($0.name).tag(String?.some($0.id)) }
                }
                TextField("Tags", text: $tagText, prompt: Text("sales, q4"))
                Picker("Priority", selection: $filter.minPriority) {
                    Text("Any").tag(0)
                    Text("Low or higher").tag(1)
                    Text("Medium or higher").tag(2)
                    Text("High").tag(3)
                }
                Picker("Due", selection: $filter.due) {
                    ForEach(TodoFilter.Due.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Containing", text: $filter.text, prompt: Text("Optional words"))
                Toggle("Include Foundry board tasks", isOn: $filter.includeBoard)
            }
            .formStyle(.grouped)
            .navigationTitle("Smart List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        filter.tags = tagText.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "#", with: "") }
                            .filter { !$0.isEmpty }
                        if let i = model.smartLists.firstIndex(where: { $0.id == filter.id }) { model.smartLists[i] = filter } else { model.smartLists.append(filter) }
                        model.show(filter: filter)
                        dismiss()
                    }
                    .disabled(filter.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(width: 460, height: 420)
        .onAppear { tagText = filter.tags.joined(separator: ", ") }
    }
}
