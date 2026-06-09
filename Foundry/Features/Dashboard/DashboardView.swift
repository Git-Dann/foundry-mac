import SwiftUI

/// Native Foundry HQ overview: greeting, headline metrics, and recent proposals.
struct DashboardView: View {
    @Environment(AppModel.self) private var model

    @State private var proposals: [ProposalListItem] = []
    @State private var clientsCount: Int?
    @State private var stats: CodeClearStats?
    @State private var state: LoadState<Void> = .idle

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 16)]

    var body: some View {
        content
            .navigationTitle("Foundry HQ")
            .task { await load() }
            .onChange(of: model.refreshToken) { Task { await load() } }
            .navigationDestination(for: ProposalRoute.self) { ProposalDetailView(id: $0.id) }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading where proposals.isEmpty && stats == nil:
            LoadingView(label: "Loading your workspace…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        default:
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let user = model.auth.currentUser {
                        Text("Welcome back, \(user.displayName.components(separatedBy: " ").first ?? user.displayName)")
                            .font(.title2.weight(.semibold))
                    }

                    LazyVGrid(columns: columns, spacing: 16) {
                        MetricCard(title: "PROPOSALS", value: "\(proposals.count)", systemImage: "doc.text", tint: .foundryBlue)
                        MetricCard(title: "CLIENTS", value: clientsCount.map(String.init) ?? "—", systemImage: "building.2", tint: .foundryPurple)
                        MetricCard(title: "CANDIDATES", value: stats.map { "\($0.total)" } ?? "—", systemImage: "person.crop.circle", tint: .blue)
                        MetricCard(title: "RECHECK DUE", value: stats.map { "\($0.recheckDue)" } ?? "—", systemImage: "clock.badge.exclamationmark", tint: .orange)
                    }

                    if !proposals.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent proposals")
                                .font(.headline)
                            ForEach(proposals.prefix(6)) { item in
                                NavigationLink(value: ProposalRoute(id: item.id)) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title).foregroundStyle(.primary)
                                            if let client = item.clientName, !client.isEmpty {
                                                Text(client).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        StatusChip(text: item.status.label, tint: item.status.tint)
                                        Text(Formatters.relative(item.updatedAt))
                                            .font(.caption).foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func load() async {
        if proposals.isEmpty && stats == nil { state = .loading }
        do {
            async let proposalsTask = model.api.listProposals(sort: "updatedAt:desc")
            async let clientsTask = try? model.api.listClients()
            async let statsTask = try? model.api.codeClearStats()

            proposals = try await proposalsTask
            clientsCount = (await clientsTask)?.count
            stats = await statsTask
            state = .loaded(())
            model.lastRefresh = Date()
        } catch {
            state = .failed(error.userMessage)
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: systemImage).foregroundStyle(tint)
                    Spacer()
                }
                Text(value)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(title)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}
