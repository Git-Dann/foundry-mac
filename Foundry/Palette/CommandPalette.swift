import SwiftUI

/// One thing the command palette can do.
struct PaletteItem: Identifiable {
    enum Kind: Int, CaseIterable, Sendable {
        case goTo, todo, list, action

        var sectionTitle: String {
            switch self {
            case .goTo: "Go to"
            case .todo: "To-dos"
            case .list: "Lists"
            case .action: "Actions"
            }
        }
    }

    var id: String
    var title: String
    var subtitle: String?
    var symbol: String
    var kind: Kind
    var action: @MainActor () -> Void
}

/// Ranks palette items against what was typed. Pure, so it is tested on its own.
enum PaletteSearch {
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Lower is better; nil means no match.
    static func score(query: String, title: String, subtitle: String?) -> Int? {
        let q = fold(query).trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return 0 }
        let t = fold(title)
        let sub = subtitle.map(fold) ?? ""
        if t.hasPrefix(q) { return 0 }
        let words = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.hasPrefix(q) }) { return 1 }
        if t.contains(q) { return 2 }
        if sub.contains(q) { return 3 }
        let tokens = q.split(whereSeparator: \.isWhitespace)
        if tokens.count > 1, tokens.allSatisfy({ t.contains($0) || sub.contains($0) }) { return 4 }
        return nil
    }

    static func rank(query: String, items: [PaletteItem]) -> [PaletteItem] {
        items.enumerated()
            .compactMap { offset, item in score(query: query, title: item.title, subtitle: item.subtitle).map { (offset, $0, item) } }
            .sorted { ($0.1, $0.0) < ($1.1, $1.0) }
            .map(\.2)
    }
}

/// Builds the palette's items from the app's real state.
@MainActor
enum PaletteItems {
    static func make(model: AppModel,
                     dismiss: @escaping () -> Void,
                     openSettings: @escaping () -> Void = {},
                     openList: ((TodoList) -> Void)? = nil) -> [PaletteItem] {
        func run(_ body: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
            { dismiss(); body() }
        }

        var items: [PaletteItem] = SidebarItem.allCases.map { destination in
            PaletteItem(id: "go.\(destination.rawValue)", title: destination.title, subtitle: nil,
                        symbol: destination.symbol, kind: .goTo,
                        action: run { model.selection = destination; model.openMainWindow() })
        }

        let lists = model.store.lists.filter { !$0.archived }
        let listNames = Dictionary(lists.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let open = model.store.items
            .filter { $0.state == .open }
            .sorted { ($0.dueAt ?? .distantFuture, $0.createdAt) < ($1.dueAt ?? .distantFuture, $1.createdAt) }
        items += open.map { c in
            var detail: [String] = []
            if let listId = c.listId, let name = listNames[listId] { detail.append(name) }
            if let due = c.dueAt { detail.append(due.formatted(.dateTime.day().month(.abbreviated))) }
            return PaletteItem(id: "todo.\(c.id)", title: c.title,
                               subtitle: detail.isEmpty ? nil : detail.joined(separator: " · "),
                               symbol: "circle", kind: .todo,
                               action: run { model.showInWindow(id: c.id) })
        }

        if let openList {
            items += lists.sorted { $0.orderKey < $1.orderKey }.map { list in
                PaletteItem(id: "list.\(list.id)", title: list.name, subtitle: list.area,
                            symbol: list.symbol ?? "list.bullet", kind: .list,
                            action: run { openList(list) })
            }
        }

        items += [
            PaletteItem(id: "action.new", title: "New To-do", subtitle: "\u{2318}N", symbol: "plus.circle", kind: .action,
                        action: run { model.openMainWindow(); model.requestQuickAddFocus() }),
            PaletteItem(id: "action.refresh", title: "Refresh", subtitle: nil, symbol: "arrow.clockwise", kind: .action,
                        action: run { Task { await model.store.refresh() } }),
            PaletteItem(id: "action.settings", title: "Settings", subtitle: "\u{2318},", symbol: "gearshape", kind: .action,
                        action: run { openSettings() }),
        ]
        return items
    }
}

/// ⌘K: search and jump. Presented as a sheet by the main window.
struct CommandPalette: View {
    private enum Source {
        case items([PaletteItem])
        case model(AppModel, openSettings: () -> Void, openList: ((TodoList) -> Void)?)
    }

    private let source: Source
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedId: String?
    @FocusState private var searchFocused: Bool

    init(model: AppModel, openSettings: @escaping () -> Void, openList: ((TodoList) -> Void)? = nil) {
        source = .model(model, openSettings: openSettings, openList: openList)
    }

    /// For previews and tests: a fixed set of items.
    init(items: [PaletteItem]) {
        source = .items(items)
    }

    private var allItems: [PaletteItem] {
        switch source {
        case .items(let items): return items
        case .model(let model, let openSettings, let openList):
            return PaletteItems.make(model: model, dismiss: { dismiss() }, openSettings: openSettings, openList: openList)
        }
    }

    /// Results grouped by section, each section in rank order.
    private var sections: [(PaletteItem.Kind, [PaletteItem])] {
        let ranked = PaletteSearch.rank(query: query, items: allItems)
        return PaletteItem.Kind.allCases.compactMap { kind in
            let rows = ranked.filter { $0.kind == kind }
            return rows.isEmpty ? nil : (kind, rows)
        }
    }

    private var flat: [PaletteItem] { sections.flatMap(\.1) }

    var body: some View {
        let rows = flat
        let current = selectedId.flatMap { id in rows.first { $0.id == id } } ?? rows.first
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                TextField("Search to-dos, lists and actions", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($searchFocused)
                    .onSubmit { activate(current) }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            if rows.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(sections, id: \.0) { kind, items in
                            Section(kind.sectionTitle) {
                                ForEach(items) { item in
                                    row(item, selected: item.id == current?.id)
                                        .id(item.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture { activate(item) }
                                        .listRowBackground(
                                            item.id == current?.id
                                                ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.18))
                                                : nil
                                        )
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .onChange(of: selectedId) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            }
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 380, idealHeight: 460)
        .onAppear { searchFocused = true }
        .onChange(of: query) { _, _ in selectedId = nil }
        .onKeyPress(.downArrow) { move(1, in: rows, from: current); return .handled }
        .onKeyPress(.upArrow) { move(-1, in: rows, from: current); return .handled }
        .onKeyPress(.return) { activate(current); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol)
                .frame(width: 20)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            Text(item.title)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func move(_ step: Int, in rows: [PaletteItem], from current: PaletteItem?) {
        guard !rows.isEmpty else { return }
        let index = current.flatMap { c in rows.firstIndex { $0.id == c.id } } ?? 0
        let next = min(max(index + step, 0), rows.count - 1)
        selectedId = rows[next].id
    }

    private func activate(_ item: PaletteItem?) {
        guard let item else { return }
        if case .items = source { dismiss() }
        item.action()
    }
}
