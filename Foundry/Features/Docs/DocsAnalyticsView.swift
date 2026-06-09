import SwiftUI

/// Navigation value for the cross-document analytics dashboard (pushed from the Docs list).
struct DocsAnalyticsRoute: Hashable {}

/// Workspace-wide Docs analytics: funnel totals, open/win rates, and leaderboards. Top documents
/// deep-link to their native detail (the enclosing stack registers `ProposalRoute`).
struct DocsAnalyticsView: View {
    @Environment(AppModel.self) private var model
    @State private var state: LoadState<DocsAnalyticsSummary> = .idle
    @State private var days = 30

    private let tiles = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        content
            .navigationTitle("Docs Analytics")
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    Picker("Range", selection: $days) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("Year").tag(365)
                    }
                }
            }
            .task(id: days) { await load() }
            .onChange(of: model.refreshToken) { Task { await load() } }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading:
            LoadingView(label: "Loading analytics…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        case .loaded(let a):
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    LazyVGrid(columns: tiles, spacing: 12) {
                        StatTile(title: "DOCUMENTS", value: "\(a.totals.documents)", tint: .foundryBlue)
                        StatTile(title: "SHARED", value: "\(a.totals.shared)", tint: .foundryPurple)
                        StatTile(title: "VIEWED", value: "\(a.totals.viewed)", tint: .blue)
                        StatTile(title: "ACCEPTED", value: "\(a.totals.accepted)", tint: .green)
                        StatTile(title: "OPEN RATE", value: a.rates.openRate.map(Formatters.percent) ?? "—", tint: .orange)
                        StatTile(title: "WIN RATE", value: a.rates.winRate.map(Formatters.percent) ?? "—", tint: .green)
                    }

                    if let time = a.rates.avgTimeToFirstOpenMs {
                        Text("Average time to first open: \(Formatters.duration(ms: time))")
                            .font(.callout).foregroundStyle(.secondary)
                    }

                    if !a.topDocuments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Top documents").font(.headline)
                            ForEach(a.topDocuments) { doc in
                                NavigationLink(value: ProposalRoute(id: doc.id)) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(doc.title).foregroundStyle(.primary).lineLimit(1)
                                            if let client = doc.clientName, !client.isEmpty {
                                                Text(client).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        StatusChip(text: doc.status.label, tint: doc.status.tint)
                                        Text("\(doc.views) views")
                                            .font(.caption).foregroundStyle(.tertiary)
                                            .frame(width: 72, alignment: .trailing)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !a.topSections.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Most-read sections").font(.headline)
                            ForEach(a.topSections) { section in
                                HStack {
                                    Text(section.sectionKey)
                                    Spacer()
                                    Text("\(section.samples) samples").font(.caption).foregroundStyle(.tertiary)
                                    Text(Formatters.duration(ms: section.avgDwellMs))
                                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                        .frame(width: 64, alignment: .trailing)
                                }
                                .padding(.vertical, 4)
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
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await model.api.documentsAnalytics(days: days))
        } catch {
            state = .failed(error.userMessage)
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text(title).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
}
