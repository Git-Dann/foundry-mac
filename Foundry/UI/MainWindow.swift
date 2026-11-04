import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        Group {
            if model.auth.isSignedIn && model.selection == .foundry {
                NavigationSplitView(columnVisibility: $columns) {
                    Sidebar()
                        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
                } detail: {
                    FeedView()
                }
            } else if model.auth.isSignedIn && model.selection == .calendar {
                // The calendar wants the whole width, so it replaces the list and detail columns.
                NavigationSplitView(columnVisibility: $columns) {
                    Sidebar()
                        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
                } detail: {
                    CalendarScreen()
                }
            } else if model.auth.isSignedIn {
                NavigationSplitView(columnVisibility: $columns) {
                    Sidebar()
                        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
                } content: {
                    CommitmentListView()
                        .navigationSplitViewColumnWidth(min: 340, ideal: 420)
                } detail: {
                    if let id = model.selectedCommitmentId, model.store.commitment(id: id) != nil {
                        CommitmentDetail(id: id).id(id)
                    } else {
                        QuietEmpty(title: "Nothing selected", detail: "Pick a to-do to see its details.", symbol: "checklist")
                    }
                }
            } else {
                SignInPrompt()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .onAppear {
            model.openWindowAction = { openWindow(id: "main") }
            model.refreshIfStale()
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let now = Date()
        let items = model.store.items
        List(selection: Binding(get: { model.selection }, set: { if let v = $0 { model.selection = v } })) {
            Section {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .badge(count(item, items: items, now: now))
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                if model.store.isOffline || !model.network.isOnline {
                    Label(model.store.pendingCount > 0 ? "Offline · \(model.store.pendingCount) to send" : "Offline", systemImage: "wifi.slash")
                }
                Button {
                    model.openFoundryWeb()
                } label: {
                    Label("Open Foundry", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    private func count(_ item: SidebarItem, items: [Commitment], now: Date) -> Int {
        switch item {
        case .today: CommitmentGrouping.dueNowCount(items, now: now)
        case .upcoming: CommitmentGrouping.sections(items, now: now, include: [.next7, .later, .noDate]).reduce(0) { $0 + $1.items.count }
        case .foundry: model.feed.mentionCount
        case .done, .calendar: 0
        }
    }
}

struct CommitmentListView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model
        let now = Date()
        let filtered = matching(model.store.items)
        List(selection: $model.selectedCommitmentId) {
            if model.selection == .today || model.selection == .upcoming {
                QuickAddField(prompt: "Add a to-do. Try “Send Acme the deck fri”", focusToken: model.focusQuickAddToken)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 4)
                if model.selection == .today {
                    SuggestionsCard().listRowSeparator(.hidden)
                }
                UndoBar().listRowSeparator(.hidden)
            }
            switch model.selection {
            case .today:
                let sections = CommitmentGrouping.sections(filtered, now: now, include: [.overdue, .today])
                if sections.isEmpty {
                    emptyRow("Nothing due today", detail: upcomingHint(now: now))
                }
                ForEach(sections, id: \.group) { s in
                    Section(s.group.title) {
                        ForEach(s.items) { CommitmentRow(commitment: $0).tag($0.id) }
                    }
                }
            case .upcoming:
                let sections = CommitmentGrouping.sections(filtered, now: now, include: [.next7, .later, .noDate, .snoozed])
                if sections.isEmpty { emptyRow("Nothing coming up", detail: nil) }
                ForEach(sections, id: \.group) { s in
                    Section(s.group.title) {
                        ForEach(s.items) { CommitmentRow(commitment: $0).tag($0.id) }
                    }
                }
            case .calendar, .foundry:
                EmptyView()
            case .done:
                let done = CommitmentGrouping.done(filtered)
                if done.isEmpty { emptyRow("Nothing done in the last two weeks", detail: nil) }
                ForEach(done) { CommitmentRow(commitment: $0).tag($0.id) }
            }
        }
        .listStyle(.inset)
        .animation(.easeOut(duration: 0.18), value: model.store.items.map(\.state))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let notes = [model.store.boardProblem, SourceProblem.summary(model.store.settings.sourceStatus)].compactMap { $0 }
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(notes, id: \.self) { SourceFootnote(text: $0) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search to-dos")
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
        .navigationTitle(model.selection.title)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.store.checkSources() }
                } label: {
                    Label("Check sources", systemImage: "arrow.clockwise")
                }
                .help(model.store.lastCheckSummary ?? "Ask Foundry to read your sources now")
                .disabled(model.store.isCheckingSources)
            }
        }
    }

    private var subtitle: String {
        if model.store.isCheckingSources { return "Checking your sources…" }
        if let e = model.store.lastError { return e }
        let now = Date()
        let due = CommitmentGrouping.dueNowCount(model.store.items, now: now)
        let board = model.store.items.filter { $0.isBoardTask && $0.state == .open }.count
        var parts: [String] = [due == 0 ? "Nothing due today" : "\(due) due today"]
        if board > 0 { parts.append("\(board) on your Foundry boards") }
        return parts.joined(separator: " · ")
    }

    private func emptyRow(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            if let detail { Text(detail).font(.callout).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, 18)
        .listRowSeparator(.hidden)
        .selectionDisabled()
    }

    private func upcomingHint(now: Date) -> String? {
        let next = CommitmentGrouping.sections(model.store.items, now: now, include: [.next7]).first?.items.first
        guard let next, let due = next.dueAt else { return nil }
        return "Next: \(next.title), \(DueText.string(due, now: now).lowercased())."
    }

    private func matching(_ items: [Commitment]) -> [Commitment] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { c in
            [c.title, c.notes, c.counterpart, c.quote, c.evidenceLabel].compactMap { $0?.lowercased() }.contains { $0.contains(q) }
        }
    }
}
