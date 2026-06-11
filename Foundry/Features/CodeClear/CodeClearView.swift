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
        Section {
            pipelineWidget
                .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private var pipelineWidget: some View {
        FoundryCard(index: 1, title: "Pipeline") {
            HStack(alignment: .bottom, spacing: 0) {
                metricCell(value: "\(stats.total)", label: "Total")
                Divider().frame(height: 40).padding(.horizontal, 16)
                metricCell(
                    value: "\(stats.recheckDue)",
                    label: "Recheck due",
                    tint: stats.recheckDue > 0 ? .red : .primary
                )
                if let avg = stats.avgThis {
                    Divider().frame(height: 40).padding(.horizontal, 16)
                    metricCell(value: String(format: "%.0f", avg), label: "Avg score")
                }
                if let pass = stats.passRateThis {
                    Divider().frame(height: 40).padding(.horizontal, 16)
                    metricCell(
                        value: String(format: "%.0f%%", pass * (pass <= 1 ? 100 : 1)),
                        label: "Pass rate"
                    )
                }
                Spacer()
            }
            .padding(14)
        }
    }

    private func metricCell(value: String, label: String, tint: Color = .primary) -> some View {
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
    }
}

private struct CandidateRow: View {
    let candidate: Candidate

    var body: some View {
        HStack(spacing: 12) {
            CandidateAvatar(url: candidate.avatarUrl, name: candidate.name)
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("@\(candidate.githubHandle) · \(candidate.primaryStack)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let score = candidate.score?.overallScore {
                Text(String(format: "%.0f", score))
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(score >= 70 ? .green : (score >= 50 ? .orange : .red))
                    .monospacedDigit()
            }
            StatusChip(text: candidate.status.label, tint: candidate.status.tint)
        }
        .padding(.vertical, 4)
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
