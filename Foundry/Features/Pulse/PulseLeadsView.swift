import SwiftUI

/// Leads captured by the public Pulse scanner — import one into the workspace as a full scan.
struct PulseLeadsView: View {
    @Environment(AppModel.self) private var model
    @State private var state: LoadState<[PulseLead]> = .idle
    @State private var busyId: String?

    var body: some View {
        content
            .task { await load() }
            .onChange(of: model.refreshToken) { Task { await load() } }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading:
            LoadingView(label: "Loading leads…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        case .loaded(let leads):
            if leads.isEmpty {
                ContentUnavailableView(
                    "No leads",
                    systemImage: "envelope",
                    description: Text("Captured emails from the public Pulse scanner appear here.")
                )
            } else {
                List {
                    ForEach(leads) { lead in
                        LeadRow(lead: lead, busy: busyId == lead.id) { await importLead(lead) }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await model.api.listPulseLeads())
            model.lastRefresh = Date()
        } catch {
            state = .failed(error.userMessage)
        }
    }

    private func importLead(_ lead: PulseLead) async {
        busyId = lead.id
        defer { busyId = nil }
        try? await model.api.importPulseLead(id: lead.id)
        await load()
    }
}

private struct LeadRow: View {
    let lead: PulseLead
    let busy: Bool
    let importAction: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            HealthBadge(score: lead.healthScore)
            VStack(alignment: .leading, spacing: 3) {
                Text(lead.email).font(.body.weight(.medium)).lineLimit(1)
                Text(lead.targetUrl).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(Formatters.relative(lead.createdAt)).font(.caption).foregroundStyle(.tertiary)
            if lead.isImported {
                StatusChip(text: "Imported", tint: .green)
            } else {
                Button { Task { await importAction() } } label: {
                    if busy { ProgressView().controlSize(.small) } else { Text("Import") }
                }
                .buttonStyle(.bordered)
                .disabled(busy)
            }
        }
        .padding(.vertical, 3)
    }
}
