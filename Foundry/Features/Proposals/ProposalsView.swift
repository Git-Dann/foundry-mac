import SwiftUI

/// Navigation value for the proposals list → detail push.
struct ProposalRoute: Hashable { let id: String }

/// Proposals list: native `List` with search, type/status filters, create sheet, and push
/// navigation to a detail screen. Reacts to the global Refresh (⌘R), New Proposal (⌘N), and
/// Search (⌘F) commands.
struct ProposalsView: View {
    @Environment(AppModel.self) private var model

    @State private var state: LoadState<[ProposalListItem]> = .idle
    @State private var search = ""
    @State private var typeFilter: DocumentType = .proposal
    @State private var statusFilter: DocumentStatus?
    @State private var showingCreate = false
    @FocusState private var searchFocused: Bool

    private var filterKey: String { "\(typeFilter.rawValue)|\(statusFilter?.rawValue ?? "all")" }

    var body: some View {
        content
            .navigationTitle("Proposals")
            .navigationSubtitle(typeFilter == .proposal ? "" : typeFilter.label)
            .searchable(text: $search, prompt: "Search proposals")
            .searchFocused($searchFocused)
            .onSubmit(of: .search) { Task { await load() } }
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink(value: DocsAnalyticsRoute()) {
                        Label("Analytics", systemImage: "chart.bar.xaxis")
                    }
                }
                ToolbarItem(placement: .secondaryAction) { filterMenu }
            }
            .task(id: filterKey) { await load() }
            .onChange(of: model.refreshToken) { Task { await load() } }
            .onChange(of: model.newProposalToken) { showingCreate = true }
            .onChange(of: model.searchToken) { searchFocused = true }
            .navigationDestination(for: ProposalRoute.self) { route in
                ProposalDetailView(id: route.id)
            }
            .navigationDestination(for: DocsAnalyticsRoute.self) { _ in DocsAnalyticsView() }
            .sheet(isPresented: $showingCreate) {
                ProposalCreateSheet { _ in
                    showingCreate = false
                    Task { await load() }
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading:
            LoadingView(label: "Loading proposals…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        case .loaded(let items):
            if items.isEmpty {
                ContentUnavailableView {
                    Label("No proposals", systemImage: "doc.text")
                } description: {
                    Text(search.isEmpty ? "Create your first \(typeFilter.label.lowercased())." : "No results for “\(search)”.")
                } actions: {
                    Button("New Proposal") { showingCreate = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(items) { item in
                        NavigationLink(value: ProposalRoute(id: item.id)) {
                            ProposalRow(item: item)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Type", selection: $typeFilter) {
                ForEach(DocumentType.selectable) { Text($0.label).tag($0) }
            }
            Divider()
            Picker("Status", selection: $statusFilter) {
                Text("All statuses").tag(DocumentStatus?.none)
                ForEach(DocumentStatus.selectable) { Text($0.label).tag(DocumentStatus?.some($0)) }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let items = try await model.api.listProposals(
                search: search.nilIfEmpty,
                status: statusFilter,
                documentType: typeFilter,
                sort: "updatedAt:desc"
            )
            state = .loaded(items)
            model.lastRefresh = Date()
        } catch {
            state = .failed(error.userMessage)
        }
    }
}

private struct ProposalRow: View {
    let item: ProposalListItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let client = item.clientName, !client.isEmpty { Text(client) }
                    if let number = item.documentNumber { Text("· \(number)") }
                    if item.documentType != .proposal { Text("· \(item.documentType.label)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            StatusChip(text: item.status.label, tint: item.status.tint)
            Text(Formatters.relative(item.updatedAt))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }
}
