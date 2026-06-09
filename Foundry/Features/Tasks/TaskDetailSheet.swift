import SwiftUI

/// Task detail: edit core fields (saved together), toggle/add subtasks, read/post comments, delete.
struct TaskDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let taskId: String
    let clientId: String
    let clientSlug: String
    let members: [WorkspaceMember]
    var onChanged: () -> Void

    @State private var detail: TaskItemDetail?
    @State private var state: LoadState<Void> = .idle

    // Editable mirrors of the task fields.
    @State private var title = ""
    @State private var details = ""
    @State private var acceptance = ""
    @State private var status: TaskStatus = .backlog
    @State private var priority: TaskPriority = .medium
    @State private var assignees: Set<String> = []
    @State private var hasDue = false
    @State private var due = Date()

    @State private var newSubtask = ""
    @State private var newComment = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                switch state {
                case .idle, .loading:
                    LoadingView(label: "Loading task…").frame(height: 220)
                case .failed(let message):
                    ErrorStateView(message: message) { Task { await load() } }.frame(height: 220)
                case .loaded:
                    editor
                }
            }
        }
        .frame(width: 560, height: 660)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Task").font(.headline)
            Spacer()
            if saving { ProgressView().controlSize(.small) }
            Button("Save") { Task { await save() } }
                .buttonStyle(.borderedProminent)
                .disabled(detail == nil || saving)
            Button("Done") { dismiss() }
        }
        .padding(16)
    }

    @ViewBuilder private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error { Text(error).foregroundStyle(.red).font(.callout) }

            TextField("Title", text: $title).textFieldStyle(.roundedBorder).font(.title3)

            HStack(spacing: 12) {
                Picker("Status", selection: $status) {
                    ForEach(TaskStatus.allCases) { Text($0.label).tag($0) }
                }.fixedSize()
                Picker("Priority", selection: $priority) {
                    ForEach(TaskPriority.allCases) { Text($0.label).tag($0) }
                }.fixedSize()
                Spacer()
            }

            LabeledContent("Assignees") { AssigneePicker(members: members, selected: $assignees) }

            Toggle("Due date", isOn: $hasDue)
            if hasDue { DatePicker("Due", selection: $due, displayedComponents: .date).labelsHidden() }

            field("Description", text: $details)
            field("Acceptance criteria", text: $acceptance)

            subtasksSection
            commentsSection

            Button(role: .destructive) { Task { await deleteTask() } } label: {
                Label("Delete task", systemImage: "trash")
            }
            .padding(.top, 4)
        }
        .padding(16)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text, axis: .vertical).lineLimit(2...6).textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder private var subtasksSection: some View {
        if let detail {
            VStack(alignment: .leading, spacing: 6) {
                Text("Subtasks").font(.headline)
                ForEach(detail.subtasks) { sub in
                    HStack(spacing: 8) {
                        Button { Task { await toggleSubtask(sub) } } label: {
                            Image(systemName: sub.status == .done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(sub.status == .done ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        Text(sub.title)
                            .strikethrough(sub.status == .done)
                            .foregroundStyle(sub.status == .done ? .secondary : .primary)
                        Spacer()
                    }
                }
                HStack {
                    TextField("Add subtask", text: $newSubtask)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await addSubtask() } }
                    Button("Add") { Task { await addSubtask() } }.disabled(newSubtask.trimmed.isEmpty)
                }
            }
        }
    }

    @ViewBuilder private var commentsSection: some View {
        if let detail {
            VStack(alignment: .leading, spacing: 6) {
                Text("Comments").font(.headline)
                ForEach(detail.comments) { comment in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(comment.author?.name ?? "—").font(.callout.weight(.medium))
                            Spacer()
                            Text(Formatters.relative(comment.createdAt)).font(.caption).foregroundStyle(.tertiary)
                        }
                        Text(comment.body).font(.callout)
                    }
                }
                HStack {
                    TextField("Add a comment", text: $newComment)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await addComment() } }
                    Button("Post") { Task { await addComment() } }.disabled(newComment.trimmed.isEmpty)
                }
            }
        }
    }

    // MARK: Actions

    private func load() async {
        if detail == nil { state = .loading }
        do {
            let task = try await model.api.getTask(id: taskId)
            detail = task
            title = task.title
            details = task.description ?? ""
            acceptance = task.acceptanceCriteria ?? ""
            status = task.status
            priority = task.priority
            assignees = Set(task.assignees.map(\.id))
            if let dueDate = task.dueDate { hasDue = true; due = dueDate } else { hasDue = false }
            state = .loaded(())
        } catch {
            state = .failed(error.userMessage)
        }
    }

    private func save() async {
        saving = true
        error = nil
        defer { saving = false }
        let update = TaskUpdate(
            title: title.trimmed.nilIfEmpty,
            description: details.trimmed.nilIfEmpty,
            acceptanceCriteria: acceptance.trimmed.nilIfEmpty,
            status: status,
            priority: priority,
            assigneeIds: Array(assignees),
            dueDate: hasDue ? ISO8601DateParser.string(from: due) : nil
        )
        do {
            _ = try await model.api.updateTask(id: taskId, update)
            onChanged()
            await load()
        } catch {
            self.error = error.userMessage
        }
    }

    private func toggleSubtask(_ sub: TaskItem) async {
        let next: TaskStatus = sub.status == .done ? .todo : .done
        _ = try? await model.api.updateTask(id: sub.id, TaskUpdate(status: next))
        await load()
        onChanged()
    }

    private func addSubtask() async {
        let text = newSubtask.trimmed
        guard !text.isEmpty else { return }
        newSubtask = ""
        _ = try? await model.api.createTask(TaskInput(clientId: clientId, title: text, parentId: taskId))
        await load()
        onChanged()
    }

    private func addComment() async {
        let text = newComment.trimmed
        guard !text.isEmpty else { return }
        newComment = ""
        _ = try? await model.api.addTaskComment(id: taskId, body: text)
        await load()
    }

    private func deleteTask() async {
        do {
            try await model.api.deleteTask(id: taskId)
            onChanged()
            dismiss()
        } catch {
            self.error = error.userMessage
        }
    }
}
