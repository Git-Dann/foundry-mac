import SwiftUI

/// "Foundry": what's happening with your clients that may need you, from what Foundry already
/// collects. Nothing here is a to-do until you make it one.
struct FeedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let feed = model.feed
        let mentions = feed.items.filter { $0.kind == .mention }
        let byClient = Dictionary(grouping: feed.items.filter { $0.kind == .clientMessage }, by: \.clientName)
            .sorted { ($0.value.first?.at ?? .distantPast) > ($1.value.first?.at ?? .distantPast) }
        List {
            if feed.items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(feed.loadedAt == nil ? "Loading…" : "All quiet. Nothing in your client channels this week.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 18)
                .listRowSeparator(.hidden)
            }
            if !feed.mail.isEmpty {
                Section("Email · unread this week") {
                    ForEach(feed.mail) { MailRow(item: $0) }
                }
            } else if let problem = feed.mailProblem, !problem.isEmpty {
                Section("Email") {
                    Label(problem, systemImage: "envelope.badge.shield.half.filled")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }
            }
            if !mentions.isEmpty {
                Section("Mentioned you") {
                    ForEach(mentions) { FeedRow(item: $0) }
                }
            }
            ForEach(byClient, id: \.key) { client, items in
                Section(client) {
                    ForEach(items.prefix(6)) { FeedRow(item: $0) }
                }
            }
        }
        .listStyle(.inset)
        .contentMargins(.vertical, 12, for: .scrollContent)
        // Messages arrive after the list first lays out; a List keeps the row heights it measured
        // for the earlier content, which overlapped rows. Re-lay out when the feed changes.
        .id(feed.items.map(\.id) + feed.mail.map(\.id))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let problem = feed.problem {
                SourceFootnote(text: problem)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .navigationTitle("Foundry")
        .navigationSubtitle("Your unread email and client Slack · no AI")
        .toolbar {
            ToolbarItem {
                Button { Task { await feed.refresh(force: true) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(feed.isLoading)
            }
        }
        .task { await feed.refresh() }
    }
}

struct FeedRow: View {
    @Environment(AppModel.self) private var model
    let item: FeedItem
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(item.author).fontWeight(.semibold)
                if item.kind == .mention { Text("· \(item.clientName)").foregroundStyle(.secondary) }
                Text(item.at.formatted(.relative(presentation: .named)))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 6)
                HStack(spacing: 8) {
                    if let link = item.link {
                        Button { NSWorkspace.shared.open(link) } label: { Image(systemName: "arrow.up.right.square") }
                            .help("Open in Slack")
                    }
                    Button { model.feed.clear(item.id) } label: { Image(systemName: "xmark") }
                        .help("Clear from this list")
                    Button("Make a to-do") {
                        model.store.add(NewCommitment(title: item.suggestedToDo, notes: String(item.text.prefix(4000)), counterpart: item.clientName))
                        model.feed.clear(item.id)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                }
                .buttonStyle(.borderless)
                .opacity(hovering ? 1 : 0.0)
            }
            .font(.callout)
            Text(item.text)
                .lineLimit(3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Make a To-do") {
                model.store.add(NewCommitment(title: item.suggestedToDo, notes: String(item.text.prefix(4000)), counterpart: item.clientName))
                model.feed.clear(item.id)
            }
            if let link = item.link { Button("Open in Slack") { NSWorkspace.shared.open(link) } }
            Divider()
            Button("Clear") { model.feed.clear(item.id) }
        }
    }
}

struct MailRow: View {
    @Environment(AppModel.self) private var model
    let item: MailItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(item.fromName).fontWeight(.semibold).lineLimit(1)
                if let d = item.date {
                    Text(d.formatted(.relative(presentation: .named))).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 6)
                if let url = item.url {
                    Button("Open in Gmail", systemImage: "arrow.up.right.square") { NSWorkspace.shared.open(url) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Open in Gmail")
                }
                Button("Make a to-do") {
                    model.store.add(NewCommitment(title: item.suggestedToDo, notes: item.url.map { "[Open the email](\($0.absoluteString))" }, counterpart: item.fromName))
                    model.feed.clearMail(item.id)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            .font(.callout)
            Text(item.subject).lineLimit(1)
            Text(item.snippet)
                .lineLimit(2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button("Make a To-do") {
                model.store.add(NewCommitment(title: item.suggestedToDo, counterpart: item.fromName))
                model.feed.clearMail(item.id)
            }
            if let url = item.url { Button("Open in Gmail") { NSWorkspace.shared.open(url) } }
            Divider()
            Button("Clear") { model.feed.clearMail(item.id) }
        }
    }
}
