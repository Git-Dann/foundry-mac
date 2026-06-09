import SwiftUI

/// Create a task for a client (with optional assignees, feature block, and due date).
struct CreateTaskSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let clientId: String
    let blocks: [FeatureBlock]
    let members: [WorkspaceMember]
    var onCreated: () -> Void

    @State private var title = ""
    @State private var details = ""
    @State private var status: TaskStatus = .backlog
    @State private var priority: TaskPriority = .medium
    @State private var assignees: Set<String> = []
    @State private var blockId: String?
    @State private var hasDue = false
    @State private var due = Date()
    @State private var submitting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New task").font(.title3.weight(.semibold))
            Form {
                TextField("Title", text: $title)
                TextField("Description", text: $details, axis: .vertical).lineLimit(2...5)
                Picker("Status", selection: $status) {
                    ForEach(TaskStatus.allCases) { Text($0.label).tag($0) }
                }
                Picker("Priority", selection: $priority) {
                    ForEach(TaskPriority.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Assignees") { AssigneePicker(members: members, selected: $assignees) }
                Picker("Feature block", selection: $blockId) {
                    Text("None").tag(String?.none)
                    ForEach(blocks) { Text($0.name).tag(String?.some($0.id)) }
                }
                Toggle("Set due date", isOn: $hasDue)
                if hasDue { DatePicker("Due", selection: $due, displayedComponents: .date) }
            }
            .formStyle(.columns)
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button { Task { await submit() } } label: {
                    if submitting { ProgressView().controlSize(.small) } else { Text("Create task") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmed.isEmpty || submitting)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func submit() async {
        submitting = true
        error = nil
        defer { submitting = false }
        let input = TaskInput(
            clientId: clientId,
            title: title.trimmed,
            description: details.trimmed.nilIfEmpty,
            status: status,
            priority: priority,
            assigneeIds: assignees.isEmpty ? nil : Array(assignees),
            featureBlockId: blockId,
            dueDate: hasDue ? ISO8601DateParser.string(from: due) : nil
        )
        do {
            _ = try await model.api.createTask(input)
            onCreated()
            dismiss()
        } catch {
            self.error = error.userMessage
        }
    }
}
