import SwiftUI

/// Navigation value: open a client's task workspace.
struct ClientTasksRoute: Hashable {
    let clientId: String
    let clientName: String
    let clientSlug: String
}

/// Per-client tasks — Kanban board + list. Status moves via the card context menu (drag is a
/// later polish). Tapping a task opens the detail sheet. New tasks via the toolbar.
struct ClientTasksView: View {
    @Environment(AppModel.self) private var model
    let clientId: String
    let clientName: String
    let clientSlug: String

    enum Mode: String, CaseIterable, Identifiable {
        case board = "Board", list = "List", gantt = "Gantt"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .board
    @State private var tasks: [TaskItem] = []
    @State private var blocks: [FeatureBlock] = []
    @State private var milestones: [Milestone] = []
    @State private var members: [WorkspaceMember] = []
    @State private var state: LoadState<Void> = .idle
    @State private var showingCreate = false
    @State private var selectedTask: TaskItem?

    private var topLevel: [TaskItem] { tasks.filter { $0.parentId == nil } }

    var body: some View {
        content
            .navigationTitle("Tasks")
            .navigationSubtitle(clientName)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingCreate = true } label: { Label("New Task", systemImage: "plus") }
                }
            }
            .task { await load() }
            .onChange(of: model.refreshToken) { Task { await load() } }
            .sheet(isPresented: $showingCreate) {
                CreateTaskSheet(clientId: clientId, blocks: blocks, members: members) { Task { await load() } }
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailSheet(taskId: task.id, clientId: clientId, clientSlug: clientSlug, members: members) { Task { await load() } }
            }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading where tasks.isEmpty:
            LoadingView(label: "Loading tasks…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        default:
            switch mode {
            case .board: if topLevel.isEmpty { emptyTasks } else { boardView }
            case .list: if topLevel.isEmpty { emptyTasks } else { listView }
            case .gantt: GanttView(blocks: blocks, milestones: milestones)
            }
        }
    }

    private var emptyTasks: some View {
        ContentUnavailableView {
            Label("No tasks", systemImage: "checklist")
        } description: {
            Text("Create the first task for \(clientName).")
        } actions: {
            Button("New Task") { showingCreate = true }.buttonStyle(.borderedProminent)
        }
    }

    private var boardView: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(TaskStatus.allCases) { status in
                    TaskColumn(
                        status: status,
                        tasks: column(status),
                        onSelect: { selectedTask = $0 },
                        onMove: { task, newStatus in await move(task, to: newStatus) }
                    )
                }
            }
            .padding(16)
        }
    }

    private var listView: some View {
        List {
            ForEach(TaskStatus.allCases) { status in
                let items = column(status)
                if !items.isEmpty {
                    Section("\(status.label) (\(items.count))") {
                        ForEach(items) { task in
                            Button { selectedTask = task } label: { TaskRow(task: task) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func column(_ status: TaskStatus) -> [TaskItem] {
        topLevel.filter { $0.status == status }.sorted { $0.orderKey < $1.orderKey }
    }

    private func load() async {
        if tasks.isEmpty { state = .loading }
        do {
            async let taskList = model.api.listTasks(clientId: clientId)
            async let blockList = try? model.api.listFeatureBlocks(clientId: clientId)
            async let milestoneList = try? model.api.listMilestones(clientId: clientId)
            async let memberList = try? model.api.listTeamMembers()
            tasks = try await taskList
            blocks = (await blockList) ?? []
            milestones = (await milestoneList) ?? []
            members = (await memberList) ?? []
            state = .loaded(())
            model.lastRefresh = Date()
        } catch {
            state = .failed(error.userMessage)
        }
    }

    private func move(_ task: TaskItem, to status: TaskStatus) async {
        let targetMax = column(status).map(\.orderKey).max() ?? 0
        do {
            _ = try await model.api.moveTask(id: task.id, status: status, orderKey: targetMax + 1)
            await load()
        } catch {
            state = .failed(error.userMessage)
        }
    }
}

private struct TaskColumn: View {
    let status: TaskStatus
    let tasks: [TaskItem]
    let onSelect: (TaskItem) -> Void
    let onMove: (TaskItem, TaskStatus) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(status.tint).frame(width: 7, height: 7)
                Text(status.label).font(.caption.weight(.semibold))
                Text("\(tasks.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            ForEach(tasks) { task in
                TaskCard(task: task)
                    .onTapGesture { onSelect(task) }
                    .contextMenu {
                        Menu("Move to") {
                            ForEach(TaskStatus.allCases.filter { $0 != status }) { target in
                                Button(target.label) { Task { await onMove(task, target) } }
                            }
                        }
                        Button("Open") { onSelect(task) }
                    }
            }
            if tasks.isEmpty {
                Text("—").font(.caption).foregroundStyle(.tertiary).padding(.vertical, 6)
            }
        }
        .frame(width: 244, alignment: .leading)
    }
}

private struct TaskCard: View {
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title).font(.callout).lineLimit(3)
            HStack(spacing: 8) {
                Circle().fill(task.priority.tint).frame(width: 6, height: 6)
                if let block = task.featureBlock {
                    Text(block.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if task.subtaskCount > 0 {
                    Label("\(task.subtaskDoneCount)/\(task.subtaskCount)", systemImage: "checklist")
                        .labelStyle(.titleAndIcon).font(.caption2).foregroundStyle(.secondary)
                }
                AssigneeStack(assignees: task.assignees)
            }
            if let due = task.dueDate {
                Text("Due \(Formatters.medium(due))").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 1))
    }
}

private struct TaskRow: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(task.priority.tint).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).lineLimit(1)
                if let block = task.featureBlock {
                    Text(block.name).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if task.subtaskCount > 0 {
                Text("\(task.subtaskDoneCount)/\(task.subtaskCount)").font(.caption).foregroundStyle(.secondary)
            }
            AssigneeStack(assignees: task.assignees)
            if let due = task.dueDate {
                Text(Formatters.relative(due)).font(.caption).foregroundStyle(.tertiary).frame(width: 56, alignment: .trailing)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Shared assignee components

/// Overlapping initials/avatar stack for a task's assignees.
struct AssigneeStack: View {
    let assignees: [TaskUserRef]
    var limit = 3

    var body: some View {
        HStack(spacing: -6) {
            ForEach(assignees.prefix(limit)) { person in
                InitialsAvatar(name: person.name, url: person.avatarUrl, size: 22)
            }
            if assignees.count > limit {
                Circle().fill(.quaternary)
                    .frame(width: 22, height: 22)
                    .overlay(Text("+\(assignees.count - limit)").font(.system(size: 9, weight: .bold)))
                    .overlay(Circle().stroke(.background, lineWidth: 1.5))
            }
        }
    }
}

struct InitialsAvatar: View {
    let name: String
    let url: String?
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let url, let link = URL(string: url) {
                AsyncImage(url: link) { $0.resizable().scaledToFill() } placeholder: { initials }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.background, lineWidth: 1.5))
    }

    private var initials: some View {
        Circle().fill(Color.foundryBlue.opacity(0.15))
            .overlay(
                Text(name.prefix(1).uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color.foundryBlue)
            )
    }
}

/// Multi-select assignee menu, bound to a set of user ids.
struct AssigneePicker: View {
    let members: [WorkspaceMember]
    @Binding var selected: Set<String>

    var body: some View {
        Menu {
            if members.isEmpty {
                Text("No team members")
            } else {
                ForEach(members) { member in
                    Button {
                        toggle(member.user.id)
                    } label: {
                        Label(member.displayName, systemImage: selected.contains(member.user.id) ? "checkmark.circle.fill" : "circle")
                    }
                }
            }
        } label: {
            if selected.isEmpty {
                Text("Unassigned").foregroundStyle(.secondary)
            } else {
                Text(selectedNames).lineLimit(1)
            }
        }
    }

    private var selectedNames: String {
        members.filter { selected.contains($0.user.id) }.map(\.displayName).joined(separator: ", ")
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}
