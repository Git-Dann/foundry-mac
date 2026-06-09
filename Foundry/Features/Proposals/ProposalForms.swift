import SwiftUI

/// Create a new document (`POST /api/proposals`). On success, calls `onCreated` with the new id.
struct ProposalCreateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onCreated: (String) -> Void

    @State private var title = ""
    @State private var type: DocumentType = .proposal
    @State private var clientName = ""
    @State private var productName = ""
    @State private var submitting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                Picker("Type", selection: $type) {
                    ForEach(DocumentType.selectable) { Text($0.label).tag($0) }
                }
                TextField("Client name", text: $clientName)
                TextField("Product name", text: $productName)
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Proposal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(title.trimmed.isEmpty || submitting)
                }
            }
        }
        .frame(width: 460, height: 360)
    }

    private func create() {
        submitting = true
        error = nil
        Task {
            defer { submitting = false }
            do {
                let created = try await model.api.createProposal(
                    ProposalCreateInput(
                        title: title.trimmed,
                        clientName: clientName.nilIfEmpty,
                        productName: productName.nilIfEmpty,
                        documentType: type
                    )
                )
                onCreated(created.id)
                dismiss()
            } catch {
                self.error = error.userMessage
            }
        }
    }
}

/// Edit document-level fields (`PATCH /api/proposals/[id]`).
struct ProposalEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let proposal: ProposalDetail
    var onSaved: () -> Void

    @State private var title: String
    @State private var status: DocumentStatus
    @State private var clientName: String
    @State private var productName: String
    @State private var version: String
    @State private var summary: String
    @State private var submitting = false
    @State private var error: String?

    init(proposal: ProposalDetail, onSaved: @escaping () -> Void) {
        self.proposal = proposal
        self.onSaved = onSaved
        _title = State(initialValue: proposal.title)
        _status = State(initialValue: proposal.status == .unknown ? .draft : proposal.status)
        _clientName = State(initialValue: proposal.clientName ?? "")
        _productName = State(initialValue: proposal.productName ?? "")
        _version = State(initialValue: proposal.version)
        _summary = State(initialValue: proposal.summary)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    Picker("Status", selection: $status) {
                        ForEach(DocumentStatus.selectable) { Text($0.label).tag($0) }
                    }
                    TextField("Version", text: $version)
                }
                Section {
                    TextField("Client name", text: $clientName)
                    TextField("Product name", text: $productName)
                }
                Section("Summary") {
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(3...8)
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Proposal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmed.isEmpty || submitting)
                }
            }
        }
        .frame(width: 520, height: 480)
    }

    private func save() {
        submitting = true
        error = nil
        Task {
            defer { submitting = false }
            do {
                let input = ProposalUpdateInput(
                    title: title.trimmed,
                    status: status,
                    productName: productName.nilIfEmpty,
                    clientName: clientName.nilIfEmpty,
                    summary: summary,
                    version: version.nilIfEmpty
                )
                _ = try await model.api.updateProposal(id: proposal.id, input)
                onSaved()
                dismiss()
            } catch {
                self.error = error.userMessage
            }
        }
    }
}
