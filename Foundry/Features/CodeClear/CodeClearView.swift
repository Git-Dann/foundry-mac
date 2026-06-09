import SwiftUI

/// CodeClear: pipeline stats + a paginated candidate roster with search/filters and a
/// read-only candidate detail. (Candidate editing stays in Foundry Web.)
struct CodeClearView: View {
    @Environment(AppModel.self) private var model

    @State private var stats: CodeClearStats?
    @State private var candidates: [Candidate] = []
    @State private var meta: CandidateListResponse.Meta?
    @State private var listState: LoadState<Void> = .idle
    @State private var search = ""
    @State private var statusFilter: PipelineStatus?
    @State private var loadingMore = false
    @FocusState private var searchFocused: Bool

    private var filterKey: String { statusFilter?.rawValue ?? "all" }

    var body: some View {
        content
            .navigationTitle("CodeClear")
            .searchable(text: $search, prompt: "Search candidates")
            .searchFocused($searchFocused)
            .onSubmit(of: .search) { Task { await reload() } }
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Picker("Status", selection: $statusFilter) {
                            Text("All statuses").tag(PipelineStatus?.none)
                            ForEach(PipelineStatus.allCases.filter { $0 != .unknown }) {
                                Text($0.label).tag(PipelineStatus?.some($0))
                            }
                        }
                    } label: { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") }
                }
            }
            .task(id: filterKey) { await reload() }
            .onChange(of: model.refreshToken) { Task { await reload() } }
            .onChange(of: model.searchToken) { searchFocused = true }
            .navigationDestination(for: Candidate.self) { CandidateDetailView(candidate: $0) }
    }

    @ViewBuilder private var content: some View {
        switch listState {
        case .idle, .loading where candidates.isEmpty:
            LoadingView(label: "Loading candidates…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await reload() } }
        default:
            List {
                if let stats { StatsSection(stats: stats) }
                Section("Candidates\(meta.map { " (\($0.total))" } ?? "")") {
                    ForEach(candidates) { candidate in
                        NavigationLink(value: candidate) { CandidateRow(candidate: candidate) }
                    }
                    if let meta, candidates.count < meta.total {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            if loadingMore { ProgressView().controlSize(.small) } else { Text("Load more") }
                        }
                        .disabled(loadingMore)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func reload() async {
        listState = .loading
        async let statsTask = try? model.api.codeClearStats()
        do {
            let response = try await model.api.listCandidates(
                query: search.nilIfEmpty, status: statusFilter, page: 1
            )
            candidates = response.items
            meta = response.meta
            stats = await statsTask
            listState = .loaded(())
            model.lastRefresh = Date()
        } catch {
            listState = .failed(error.userMessage)
        }
    }

    private func loadMore() async {
        guard let meta, candidates.count < meta.total, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let next = try await model.api.listCandidates(
                query: search.nilIfEmpty, status: statusFilter, page: meta.page + 1
            )
            candidates.append(contentsOf: next.items)
            self.meta = next.meta
        } catch {
            // Keep the existing list; surface the error inline next refresh.
        }
    }
}

private struct StatsSection: View {
    let stats: CodeClearStats

    var body: some View {
        Section("Pipeline") {
            LabeledContent("Total candidates", value: "\(stats.total)")
            LabeledContent("Recheck due", value: "\(stats.recheckDue)")
            if let avg = stats.avgThis {
                LabeledContent("Avg score (this period)", value: String(format: "%.0f", avg))
            }
            if let pass = stats.passRateThis {
                LabeledContent("Pass rate", value: String(format: "%.0f%%", pass * (pass <= 1 ? 100 : 1)))
            }
            if !stats.byStatus.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(stats.byStatus) { entry in
                            StatusChip(text: "\(entry.status.label) · \(entry.count)", tint: entry.status.tint)
                        }
                    }
                }
            }
        }
    }
}

private struct CandidateRow: View {
    let candidate: Candidate

    var body: some View {
        HStack(spacing: 12) {
            CandidateAvatar(url: candidate.avatarUrl, name: candidate.name)
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.name).font(.body.weight(.medium)).lineLimit(1)
                Text("@\(candidate.githubHandle) · \(candidate.primaryStack)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let score = candidate.score?.overallScore {
                Text(String(format: "%.0f", score)).font(.callout.weight(.semibold)).monospacedDigit()
            }
            StatusChip(text: candidate.status.label, tint: candidate.status.tint)
        }
        .padding(.vertical, 3)
    }
}

struct CandidateAvatar: View {
    let url: String?
    let name: String

    var body: some View {
        Group {
            if let url, let link = URL(string: url) {
                AsyncImage(url: link) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
    }

    private var initials: some View {
        Circle()
            .fill(Color.foundryBlue.opacity(0.15))
            .overlay(
                Text(name.prefix(1).uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.foundryBlue)
            )
    }
}
