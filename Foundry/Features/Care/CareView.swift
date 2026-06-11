import SwiftUI

/// Care: support-client roster with a bento overview strip. Tap a client for conversations,
/// tickets, draft actions, and analytics.
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
                // Overview bento row — metric widgets inside a list section
                if let dashboard {
                    Section {
                        overviewWidgets(dashboard)
                            .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    if !dashboard.recentConversations.isEmpty {
                        Section {
                            ForEach(dashboard.recentConversations) { conv in
                                ConversationRow(conversation: conv)
                            }
                        } header: {
                            Text("01 // RECENT")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .tracking(1.2)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                }

                Section {
                    ForEach(clients) { client in
                        NavigationLink(value: client) { CareClientRow(client: client) }
                    }
                } header: {
                    Text("02 // CLIENTS")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
            .listStyle(.inset)
        }
    }

    // MARK: - Overview widgets (bento strip)

    @ViewBuilder
    private func overviewWidgets(_ dashboard: SupportDashboard) -> some View {
        HStack(spacing: 10) {
            overviewMetric(
                value: "\(dashboard.clientCount)",
                label: "Clients"
            )
            Divider().frame(height: 40)
            overviewMetric(
                value: "\(dashboard.openTicketCount)",
                label: "Open tickets",
                tint: dashboard.openTicketCount > 0 ? .orange : .primary
            )
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func overviewMetric(value: String, label: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Load

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

// MARK: - CareClientRow

private struct CareClientRow: View {
    let client: SupportClient

    var body: some View {
        HStack(spacing: 12) {
            InitialAvatar(name: client.name, size: 30, tint: .foundryBlue)

            VStack(alignment: .leading, spacing: 3) {
                Text(client.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let used = client.supportDaysUsed, let total = client.supportDaysPerMonth, total > 0 {
                    Text("\(used) / \(total) days")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let unread = client.unreadCount, unread > 0 {
                UnreadDot(count: unread)
            }
            StatusChip(
                text: client.isActive ? "Active" : "Inactive",
                tint: client.isActive ? .green : .secondary
            )
        }
        .padding(.vertical, 3)
    }
}

// MARK: - ConversationRow

private struct ConversationRow: View {
    let conversation: SupportDashboard.DashboardConversation

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: conversation.source.systemImage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.subject.isEmpty ? conversation.customerLabel : conversation.subject)
                    .font(.body.weight(conversation.unread ? .semibold : .regular))
                    .lineLimit(1)
                Text("\(conversation.client.name) · \(conversation.customerLabel)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if conversation.unread {
                    Circle().fill(Color.foundryBlue).frame(width: 7, height: 7)
                }
                Text(Formatters.relative(conversation.receivedAt))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
