import SwiftUI

/// Native proposal detail. Shows document-level fields, sections, costing totals, timeline and
/// links. Document-level fields + status are editable natively; the rich section editor opens
/// in Foundry Web ("Edit in Foundry Web").
struct ProposalDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let id: String

    @State private var state: LoadState<ProposalDetail> = .idle
    @State private var showingEdit = false
    @State private var statusUpdating = false

    var body: some View {
        content
            .navigationTitle(state.value?.title ?? "Proposal")
            .navigationSubtitle(state.value?.documentNumber ?? "")
            .toolbar { toolbar }
            .task { await load() }
            .onChange(of: model.refreshToken) { Task { await load() } }
            .sheet(isPresented: $showingEdit) {
                if let proposal = state.value {
                    ProposalEditSheet(proposal: proposal) { Task { await load() } }
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading:
            LoadingView(label: "Loading proposal…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        case .loaded(let proposal):
            Form {
                overviewSection(proposal)
                if !proposal.summary.isEmpty {
                    Section("Summary") { Text(proposal.summary).font(.callout) }
                }
                costingSection(proposal)
                if !proposal.timelinePhases.isEmpty { timelineSection(proposal) }
                sectionsSection(proposal)
                if !proposal.links.isEmpty { linksSection(proposal) }
            }
            .formStyle(.grouped)
        }
    }

    private func overviewSection(_ p: ProposalDetail) -> some View {
        Section("Overview") {
            LabeledContent("Status") { StatusChip(text: p.status.label, tint: p.status.tint) }
            if let client = p.clientName, !client.isEmpty { LabeledContent("Client", value: client) }
            if let product = p.productName, !product.isEmpty { LabeledContent("Product", value: product) }
            LabeledContent("Type", value: p.documentType.label)
            LabeledContent("Version", value: p.version)
            if let owner = p.metadata?.owner, !owner.isEmpty { LabeledContent("Owner", value: owner) }
            LabeledContent("Updated", value: Formatters.medium(p.updatedAt))
            if !p.labels.isEmpty { LabeledContent("Labels", value: p.labels.joined(separator: ", ")) }
            if p.isShared { LabeledContent("Sharing", value: "Share link active") }
        }
    }

    private func costingSection(_ p: ProposalDetail) -> some View {
        Section("Costing") {
            if p.costLineItems.isEmpty {
                Text("No cost line items.").foregroundStyle(.secondary)
            } else {
                ForEach(p.costLineItems) { item in
                    LabeledContent {
                        Text(Formatters.currency(item.subtotal, code: "GBP"))
                            .monospacedDigit()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.itemName)
                            Text("\(item.category) · \(item.costKind == "RECURRING" ? "recurring" : "one-off")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("One-off total", value: Formatters.currency(p.oneOffTotal, code: "GBP"))
                    .fontWeight(.semibold)
                if p.recurringTotal > 0 {
                    LabeledContent("Recurring total", value: Formatters.currency(p.recurringTotal, code: "GBP"))
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func timelineSection(_ p: ProposalDetail) -> some View {
        Section("Timeline") {
            ForEach(p.timelinePhases) { phase in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(phase.name).fontWeight(.medium)
                        Spacer()
                        Text(phase.duration).font(.caption).foregroundStyle(.secondary)
                    }
                    if !phase.summary.isEmpty {
                        Text(phase.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func sectionsSection(_ p: ProposalDetail) -> some View {
        Section("Sections (\(p.sections.count))") {
            ForEach(p.sections) { section in
                HStack {
                    Image(systemName: section.isVisible ? "eye" : "eye.slash")
                        .foregroundStyle(section.isVisible ? .secondary : .tertiary)
                        .imageScale(.small)
                    Text(section.title)
                    Spacer()
                    Text(section.key).font(.caption.monospaced()).foregroundStyle(.tertiary)
                }
            }
            Text("Edit section content in Foundry Web.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func linksSection(_ p: ProposalDetail) -> some View {
        Section("Links") {
            ForEach(p.links) { link in
                if let url = URL(string: link.url) {
                    Link(link.label.isEmpty ? link.url : link.label, destination: url)
                } else {
                    Text(link.label)
                }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                ForEach(DocumentStatus.selectable) { status in
                    Button(status.label) { Task { await setStatus(status) } }
                }
            } label: {
                Label("Status", systemImage: "flag")
            }
            .disabled(state.value == nil || statusUpdating)
        }
        ToolbarItem(placement: .secondaryAction) {
            Button {
                openWindow(id: "foundry-web", value: WebDestination(path: "app/docs/\(id)", title: state.value?.title ?? "Proposal"))
            } label: {
                Label("Edit in Foundry Web", systemImage: "safari")
            }
            .buttonStyle(.glass)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showingEdit = true } label: { Label("Edit", systemImage: "pencil") }
                .disabled(state.value == nil)
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await model.api.getProposal(id: id))
        } catch {
            state = .failed(error.userMessage)
        }
    }

    private func setStatus(_ status: DocumentStatus) async {
        statusUpdating = true
        defer { statusUpdating = false }
        do {
            let updated = try await model.api.updateProposal(id: id, ProposalUpdateInput(status: status))
            state = .loaded(updated)
        } catch {
            state = .failed(error.userMessage)
        }
    }
}
