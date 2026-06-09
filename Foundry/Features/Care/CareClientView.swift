import SwiftUI

/// A support client's workspace: Conversations · Tickets · Drafts · Analytics. The monthly report
/// builder stays in Foundry Web ("Report builder").
struct CareClientView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let client: SupportClient

    enum Tab: String, CaseIterable, Identifiable {
        case conversations = "Conversations", tickets = "Tickets", drafts = "Drafts", analytics = "Analytics"
        var id: String { rawValue }
    }
    @State private var tab: Tab = .conversations

    var body: some View {
        Group {
            switch tab {
            case .conversations: CareConversationsList(clientId: client.id)
            case .tickets: CareTicketsList(clientId: client.id)
            case .drafts: CareDraftsList(clientId: client.id)
            case .analytics: CareAnalyticsView(clientId: client.id)
            }
        }
        .navigationTitle(client.name)
        .navigationSubtitle("Care")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    openWindow(value: WebDestination(path: "app/care", title: "Care · \(client.name)"))
                } label: { Label("Report builder", systemImage: "doc.richtext") }
            }
        }
        .navigationDestination(for: SupportConversation.self) { conversation in
            ConversationThreadView(clientId: client.id, conversation: conversation)
        }
    }
}

// MARK: - Conversations

private struct CareConversationsList: View {
    @Environment(AppModel.self) private var model
    let clientId: String
    @State private var conversations: [SupportConversation] = []
    @State private var state: LoadState<Void> = .idle

    var body: some View {
        Group {
            switch state {
            case .idle, .loading where conversations.isEmpty: LoadingView(label: "Loading conversations…")
            case .failed(let m): ErrorStateView(message: m) { Task { await load() } }
            default:
                if conversations.isEmpty {
                    ContentUnavailableView("No conversations", systemImage: "bubble.left.and.bubble.right")
                } else {
                    List {
                        ForEach(conversations) { conversation in
                            NavigationLink(value: conversation) { ConversationRow(conversation: conversation) }
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .task { await load() }
        .onChange(of: model.refreshToken) { Task { await load() } }
    }

    private func load() async {
        if conversations.isEmpty { state = .loading }
        do { conversations = try await model.api.listSupportConversations(clientId: clientId); state = .loaded(()) }
        catch { state = .failed(error.userMessage) }
    }
}

private struct ConversationRow: View {
    let conversation: SupportConversation
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: conversation.source.systemImage).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if conversation.unread { Circle().fill(Color.foundryBlue).frame(width: 6, height: 6) }
                    Text(conversation.subject.isEmpty ? conversation.customerLabel : conversation.subject).fontWeight(conversation.unread ? .semibold : .regular).lineLimit(1)
                }
                Text(conversation.preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Circle().fill(conversation.sentiment.tint).frame(width: 6, height: 6)
            Text(Formatters.relative(conversation.receivedAt)).font(.caption).foregroundStyle(.tertiary).frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Thread

struct ConversationThreadView: View {
    @Environment(AppModel.self) private var model
    let clientId: String
    let conversation: SupportConversation

    @State private var messages: [SupportMessage] = []
    @State private var state: LoadState<Void> = .idle
    @State private var compose = ""
    @State private var sending = false
    @State private var drafting = false

    var body: some View {
        VStack(spacing: 0) {
            switch state {
            case .idle, .loading where messages.isEmpty: LoadingView(label: "Loading messages…")
            case .failed(let m): ErrorStateView(message: m) { Task { await load() } }
            default:
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { MessageBubble(message: $0) }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            composer
        }
        .navigationTitle(conversation.subject.isEmpty ? conversation.customerLabel : conversation.subject)
        .navigationSubtitle(conversation.customerLabel)
        .task { await load() }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Reply…", text: $compose, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
            Button { Task { await draft() } } label: {
                if drafting { ProgressView().controlSize(.small) } else { Label("AI draft", systemImage: "sparkles") }
            }
            .help("Generate an AI reply")
            .disabled(drafting || sending)
            Button { Task { await send() } } label: {
                if sending { ProgressView().controlSize(.small) } else { Label("Send", systemImage: "paperplane.fill") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(compose.trimmed.isEmpty || sending)
        }
        .padding(12)
    }

    private func load() async {
        if messages.isEmpty { state = .loading }
        do { messages = try await model.api.listSupportMessages(clientId: clientId, conversationId: conversation.id); state = .loaded(()) }
        catch { state = .failed(error.userMessage) }
    }

    private func draft() async {
        drafting = true; defer { drafting = false }
        if let text = try? await model.api.supportAIDraft(clientId: clientId, conversationId: conversation.id) {
            compose = text
        }
    }

    private func send() async {
        let text = compose.trimmed
        guard !text.isEmpty else { return }
        sending = true; defer { sending = false }
        let author = model.auth.currentUser?.displayName ?? "Gitwork"
        if (try? await model.api.sendSupportMessage(clientId: clientId, conversationId: conversation.id, authorLabel: author, body: text)) != nil {
            compose = ""
            await load()
        }
    }
}

private struct MessageBubble: View {
    let message: SupportMessage
    private var outbound: Bool { message.direction == .outbound }

    var body: some View {
        HStack {
            if outbound { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 3) {
                Text(message.authorLabel).font(.caption2).foregroundStyle(.secondary)
                Text(message.body).font(.callout).textSelection(.enabled)
                Text(Formatters.medium(message.createdAt)).font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(outbound ? Color.foundryBlue.opacity(0.14) : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            if !outbound { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Tickets

private struct CareTicketsList: View {
    @Environment(AppModel.self) private var model
    let clientId: String
    @State private var tickets: [SupportTicket] = []
    @State private var state: LoadState<Void> = .idle

    var body: some View {
        Group {
            switch state {
            case .idle, .loading where tickets.isEmpty: LoadingView(label: "Loading tickets…")
            case .failed(let m): ErrorStateView(message: m) { Task { await load() } }
            default:
                if tickets.isEmpty {
                    ContentUnavailableView("No tickets", systemImage: "ticket")
                } else {
                    List {
                        ForEach(TicketStatus.selectable) { status in
                            let group = tickets.filter { $0.status == status }
                            if !group.isEmpty {
                                Section("\(status.label) (\(group.count))") {
                                    ForEach(group) { ticket in TicketRow(ticket: ticket) { await setStatus(ticket, $0) } }
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .task { await load() }
        .onChange(of: model.refreshToken) { Task { await load() } }
    }

    private func load() async {
        if tickets.isEmpty { state = .loading }
        do { tickets = try await model.api.listSupportTickets(clientId: clientId); state = .loaded(()) }
        catch { state = .failed(error.userMessage) }
    }

    private func setStatus(_ ticket: SupportTicket, _ status: TicketStatus) async {
        _ = try? await model.api.updateSupportTicket(clientId: clientId, ticketId: ticket.id, status: status)
        await load()
    }
}

private struct TicketRow: View {
    let ticket: SupportTicket
    let setStatus: (TicketStatus) async -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(ticket.priority.tint).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(ticket.title).lineLimit(1)
                HStack(spacing: 6) {
                    if let customer = ticket.customerLabel, !customer.isEmpty { Text(customer) }
                    if let type = ticket.issueType, !type.isEmpty { Text("· \(type)") }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            StatusChip(text: ticket.priority.label, tint: ticket.priority.tint)
            Menu {
                ForEach(TicketStatus.selectable) { status in
                    Button(status.label) { Task { await setStatus(status) } }
                }
            } label: {
                StatusChip(text: ticket.status.label, tint: ticket.status.tint)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Drafts

private struct CareDraftsList: View {
    @Environment(AppModel.self) private var model
    let clientId: String
    @State private var drafts: [SupportDraftAction] = []
    @State private var state: LoadState<Void> = .idle
    @State private var busyId: String?

    var body: some View {
        Group {
            switch state {
            case .idle, .loading where drafts.isEmpty: LoadingView(label: "Loading drafts…")
            case .failed(let m): ErrorStateView(message: m) { Task { await load() } }
            default:
                if drafts.isEmpty {
                    ContentUnavailableView("No draft actions", systemImage: "tray")
                } else {
                    List {
                        ForEach(drafts) { draft in
                            DraftRow(draft: draft, busy: busyId == draft.id) { status in await update(draft, status) }
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .task { await load() }
        .onChange(of: model.refreshToken) { Task { await load() } }
    }

    private func load() async {
        if drafts.isEmpty { state = .loading }
        do { drafts = try await model.api.listSupportDraftActions(clientId: clientId); state = .loaded(()) }
        catch { state = .failed(error.userMessage) }
    }

    private func update(_ draft: SupportDraftAction, _ status: DraftActionStatus) async {
        busyId = draft.id; defer { busyId = nil }
        _ = try? await model.api.updateSupportDraftAction(clientId: clientId, draftId: draft.id, status: status)
        await load()
    }
}

private struct DraftRow: View {
    let draft: SupportDraftAction
    let busy: Bool
    let update: (DraftActionStatus) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(draft.title).fontWeight(.medium).lineLimit(1)
                Spacer()
                StatusChip(text: draft.risk.label, tint: draft.risk == .high ? .red : (draft.risk == .medium ? .orange : .secondary))
                StatusChip(text: draft.status.label, tint: draft.status == .pendingApproval ? .orange : (draft.status == .approved || draft.status == .sent ? .green : .secondary))
            }
            Text(draft.body).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            if draft.status == .pendingApproval {
                HStack {
                    Spacer()
                    Button("Reject") { Task { await update(.rejected) } }.disabled(busy)
                    Button("Approve") { Task { await update(.approved) } }.buttonStyle(.borderedProminent).disabled(busy)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Analytics

private struct CareAnalyticsView: View {
    @Environment(AppModel.self) private var model
    let clientId: String
    @State private var snapshot: SupportAnalyticsSnapshot?
    @State private var state: LoadState<Void> = .idle
    @State private var month: String = ""

    var body: some View {
        Group {
            switch state {
            case .idle, .loading: LoadingView(label: "Loading analytics…")
            case .failed(let m): ErrorStateView(message: m) { Task { await load() } }
            case .loaded:
                if let snapshot, !snapshot.metrics.isEmpty {
                    List {
                        ForEach(groupedKeys(snapshot), id: \.self) { group in
                            Section(group) {
                                ForEach(snapshot.metrics.filter { ($0.group ?? "Metrics") == group }) { metric in
                                    MetricRow(metric: metric)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                } else {
                    ContentUnavailableView("No analytics", systemImage: "chart.bar", description: Text("Connect a product-analytics source for this client in Foundry Web."))
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Picker("Month", selection: $month) {
                    ForEach(recentMonths(6), id: \.self) { Text($0).tag($0) }
                }
            }
        }
        .task { if month.isEmpty { month = recentMonths(1).first ?? "" }; await load() }
        .onChange(of: month) { Task { await load() } }
    }

    private func groupedKeys(_ snapshot: SupportAnalyticsSnapshot) -> [String] {
        var seen: [String] = []
        for metric in snapshot.metrics {
            let group = metric.group ?? "Metrics"
            if !seen.contains(group) { seen.append(group) }
        }
        return seen
    }

    private func recentMonths(_ count: Int) -> [String] {
        let cal = Calendar.current
        return (0..<count).compactMap { offset in
            guard let date = cal.date(byAdding: .month, value: -offset, to: Date()) else { return nil }
            let c = cal.dateComponents([.year, .month], from: date)
            return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        }
    }

    private func load() async {
        guard !month.isEmpty else { return }
        state = .loading
        do { snapshot = try await model.api.supportAnalytics(clientId: clientId, month: month); state = .loaded(()) }
        catch { state = .failed(error.userMessage) }
    }
}

private struct MetricRow: View {
    let metric: SupportAnalyticsSnapshot.Metric

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Text(valueText).monospacedDigit().fontWeight(.medium)
                if let trend = metric.trendPct {
                    let up = trend >= 0
                    Label(String(format: "%.0f%%", abs(trend)), systemImage: up ? "arrow.up" : "arrow.down")
                        .font(.caption).foregroundStyle(up ? .green : .red).labelStyle(.titleAndIcon)
                }
            }
        } label: {
            Text(metric.label)
        }
    }

    private var valueText: String {
        let number = metric.value == metric.value.rounded() ? String(format: "%.0f", metric.value) : String(format: "%.1f", metric.value)
        if let unit = metric.unit, !unit.isEmpty { return "\(number) \(unit)" }
        return number
    }
}
