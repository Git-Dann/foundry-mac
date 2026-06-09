import SwiftUI

/// Care: the support-client roster + a live dashboard summary. Tap a client to open its
/// conversations, tickets, draft actions, and analytics.
struct CareView: View {
    @Environment(AppModel.self) private var model
    @State private var clients: [SupportClient] = []
    @State private var dashboard: SupportDashboard?
    @State private var state: LoadState<Void> = .idle

    var body: some View {
        content
            .navigationTitle("Care")
            .task { await load() }
            .onChange(of: model.refreshToken) { Task { await load() } }
            .navigationDestination(for: SupportClient.self) { CareClientView(client: $0) }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading where clients.isEmpty:
            LoadingView(label: "Loading support…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        default:
            List {
                if let dashboard {
                    Section("Overview") {
                        LabeledContent("Active clients", value: "\(dashboard.clientCount)")
                        LabeledContent("Open tickets", value: "\(dashboard.openTicketCount)")
                    }
                    if !dashboard.recentConversations.isEmpty {
                        Section("Recent conversations") {
                            ForEach(dashboard.recentConversations) { conversation in
                                HStack(spacing: 10) {
                                    Image(systemName: conversation.source.systemImage).foregroundStyle(.secondary).frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(conversation.subject.isEmpty ? conversation.customerLabel : conversation.subject).lineLimit(1)
                                        Text("\(conversation.client.name) · \(conversation.customerLabel)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if conversation.unread { Circle().fill(Color.foundryBlue).frame(width: 7, height: 7) }
                                    Text(Formatters.relative(conversation.receivedAt)).font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
                Section("Clients") {
                    ForEach(clients) { client in
                        NavigationLink(value: client) { CareClientRow(client: client) }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func load() async {
        if clients.isEmpty { state = .loading }
        do {
            async let clientList = model.api.listSupportClients()
            async let dash = try? model.api.supportDashboard()
            clients = try await clientList
            dashboard = await dash
            state = .loaded(())
            model.lastRefresh = Date()
        } catch {
            state = .failed(error.userMessage)
        }
    }
}

private struct CareClientRow: View {
    let client: SupportClient

    var body: some View {
        HStack(spacing: 10) {
            Text(client.name).fontWeight(.medium)
            if let used = client.supportDaysUsed, let total = client.supportDaysPerMonth, total > 0 {
                Text("\(used)/\(total) days").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let unread = client.unreadCount, unread > 0 {
                Text("\(unread)")
                    .font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.foundryBlue, in: Capsule())
            }
            StatusChip(text: client.isActive ? "Active" : "Inactive", tint: client.isActive ? .green : .secondary)
        }
        .padding(.vertical, 2)
    }
}
