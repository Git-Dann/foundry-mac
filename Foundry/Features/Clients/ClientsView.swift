import SwiftUI

struct ClientRoute: Hashable { let slug: String }

/// Clients list with search, status filter, create, and push navigation to detail.
struct ClientsView: View {
    @Environment(AppModel.self) private var model

    @State private var state: LoadState<[ClientListItem]> = .idle
    @State private var search = ""
    @State private var statusFilter: WorkspaceClientStatus?
    @State private var showingCreate = false
    @FocusState private var searchFocused: Bool

    private var filterKey: String { statusFilter?.rawValue ?? "all" }

    var body: some View {
        content
            .navigationTitle("Clients")
            .searchable(text: $search, prompt: "Search clients")
            .searchFocused($searchFocused)
            .onSubmit(of: .search) { Task { await load() } }
            .toolbar {
                ToolbarItem(placement: .secondaryAction) { filterMenu }
                ToolbarItem(placement: .secondaryAction) {
                    Button { showingCreate = true } label: { Label("New Client", systemImage: "plus") }
                }
            }
            .task(id: filterKey) { await load() }
            .onChange(of: model.refreshToken) { Task { await load() } }
            .onChange(of: model.searchToken) { searchFocused = true }
            .navigationDestination(for: ClientRoute.self) { ClientDetailView(slug: $0.slug) }
            .navigationDestination(for: ProposalRoute.self) { ProposalDetailView(id: $0.id) }
            .sheet(isPresented: $showingCreate) {
                ClientCreateSheet { showingCreate = false; Task { await load() } }
            }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading:
            LoadingView(label: "Loading clients…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        case .loaded(let items):
            if items.isEmpty {
                ContentUnavailableView {
                    Label("No clients", systemImage: "building.2")
                } description: {
                    Text(search.isEmpty ? "Add your first client." : "No results for “\(search)”.")
                } actions: {
                    Button("New Client") { showingCreate = true }.buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(items) { item in
                        NavigationLink(value: ClientRoute(slug: item.slug)) { ClientRow(item: item) }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Status", selection: $statusFilter) {
                Text("All statuses").tag(WorkspaceClientStatus?.none)
                ForEach(WorkspaceClientStatus.selectable) { Text($0.label).tag(WorkspaceClientStatus?.some($0)) }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let items = try await model.api.listClients(search: search.nilIfEmpty, status: statusFilter)
            state = .loaded(items)
            model.lastRefresh = Date()
        } catch {
            state = .failed(error.userMessage)
        }
    }
}

private struct ClientRow: View {
    let item: ClientListItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(item.proposalCount) doc\(item.proposalCount == 1 ? "" : "s")")
                    if item.hasCareClient { Text("· Care") }
                    if !item.repoUrls.isEmpty { Text("· \(item.repoUrls.count) repo\(item.repoUrls.count == 1 ? "" : "s")") }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            StatusChip(text: item.status.label, tint: item.status.tint)
        }
        .padding(.vertical, 3)
    }
}
