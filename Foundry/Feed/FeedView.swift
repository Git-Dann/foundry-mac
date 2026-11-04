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
        .id(feed.items.map(\.id))
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
        .navigationSubtitle("From your client Slack channels · no AI")
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
