import SwiftUI

extension TodoList {
    /// The list's colour name ("red", "teal"…) as a system colour. Unknown or missing reads as the accent.
    var tint: Color {
        switch color?.lowercased() {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "cyan": .cyan
        case "blue": .blue
        case "indigo": .indigo
        case "purple": .purple
        case "pink": .pink
        case "brown": .brown
        case "gray", "grey": .gray
        default: .accentColor
        }
    }
}

/// Your own open to-dos as columns: Inbox, then one column per list. Drag a card between
/// columns to move it to that list. Board tasks are left out: their list can't change.
struct KanbanView: View {
    @Environment(AppModel.self) private var model

    private var lists: [TodoList] {
        model.store.lists.filter { !$0.archived }.sorted { $0.orderKey < $1.orderKey }
    }

    private var openOwn: [Commitment] {
        let now = Date()
        return model.store.items
            .filter { $0.state == .open && !$0.isBoardTask && !$0.isSnoozed(at: now) }
            .sorted { ($0.orderKey, $0.createdAt) < ($1.orderKey, $1.createdAt) }
    }

    var body: some View {
        if lists.isEmpty {
            ContentUnavailableView(
                "No Lists Yet",
                systemImage: "rectangle.split.3x1",
                description: Text("Create a list to see your board.")
            )
        } else {
            let items = openOwn
            let known = Set(lists.map(\.id))
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    KanbanColumn(
                        title: "Inbox", symbol: "tray", tint: .secondary, listId: nil,
                        items: items.filter { $0.listId == nil || !known.contains($0.listId!) }
                    )
                    ForEach(lists) { list in
                        KanbanColumn(
                            title: list.name, symbol: list.symbol ?? "list.bullet", tint: list.tint, listId: list.id,
                            items: items.filter { $0.listId == list.id }
                        )
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.visible)
        }
    }
}

private struct KanbanColumn: View {
    @Environment(AppModel.self) private var model
    let title: String
    let symbol: String
    let tint: Color
    let listId: String?
    let items: [Commitment]

    @State private var targeted = false
    @State private var adding = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Spacer()
                Text(items.count, format: .number)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 4)

            ScrollView(.vertical) {
                LazyVStack(spacing: 12) {
                    ForEach(items) { item in
                        KanbanCard(commitment: item)
                    }
                    footer
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.never)
        }
        .padding(12)
        .frame(width: 280, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(targeted ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.fill.quinary),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.smooth, value: targeted)
        .dropDestination(for: String.self) { ids, _ in
            var moved = false
            for id in ids {
                guard let c = model.store.commitment(id: id), !c.isBoardTask, c.listId != listId else { continue }
                withAnimation(.smooth) {
                    model.store.update(id, CommitmentPatch(listId: listId.map { .set($0) } ?? .clear))
                }
                moved = true
            }
            return moved
        } isTargeted: { targeted = $0 }
    }

    @ViewBuilder private var footer: some View {
        if adding {
            TextField("New to-do", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit(submit)
                .onExitCommand { cancel() }
                .onAppear { fieldFocused = true }
        } else {
            Button("Add To-do", systemImage: "plus") {
                withAnimation(.smooth) { adding = true }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("Add a to-do to \(title)")
        }
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            withAnimation(.smooth) {
                _ = model.store.add(text: text, defaults: NewCommitment(title: "", listId: listId))
            }
        }
        draft = ""
        fieldFocused = true
        if text.isEmpty { cancel() }
    }

    private func cancel() {
        draft = ""
        withAnimation(.smooth) { adding = false }
    }
}

/// One to-do on the board: tick, title, meta, priority marks.
private struct KanbanCard: View {
    @Environment(AppModel.self) private var model
    let commitment: Commitment

    var body: some View {
        let lines = Display.lines(for: commitment)
        let selected = model.selectedCommitmentId == commitment.id
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            CompleteButton(done: false) { model.complete(commitment.id) }
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 4) {
                Text(lines.title)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RowMeta(commitment: commitment, subtitle: lines.subtitle)
            }
            if commitment.priority > 0 {
                PriorityMarks(priority: commitment.priority)
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.tint, lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { model.selectedCommitmentId = commitment.id }
        .draggable(commitment.id)
        .contextMenu { CommitmentContextMenu(commitment: commitment) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// "!", "!!" or "!!!", the same marks quick add uses.
struct PriorityMarks: View {
    let priority: Int

    var body: some View {
        Text(String(repeating: "!", count: min(max(priority, 0), 3)))
            .font(.caption.weight(.bold))
            .foregroundStyle(priority >= 3 ? .red : .orange)
            .accessibilityLabel(priority >= 3 ? "High priority" : (priority == 2 ? "Medium priority" : "Low priority"))
    }
}
