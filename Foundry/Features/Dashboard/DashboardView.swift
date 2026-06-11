import SwiftUI

/// Foundry HQ — bento-grid dashboard matching the DESIGN.md FoundryCard pattern.
/// Numbered widget cards, serif stat figures, mono data labels.
struct DashboardView: View {
    @Environment(AppModel.self) private var model

    @State private var proposals: [ProposalListItem] = []
    @State private var clientsCount: Int?
    @State private var stats: CodeClearStats?
    @State private var aiCost: AiCostSummary?
    @State private var state: LoadState<Void> = .idle

    private var isSuperAdmin: Bool { model.auth.currentUser?.role == "SUPER_ADMIN" }
    private let twoCol = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        content
            .navigationTitle("Foundry HQ")
            .task { await load() }
            .onChange(of: model.refreshToken) { Task { await load() } }
            .navigationDestination(for: ProposalRoute.self) { ProposalDetailView(id: $0.id) }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading where proposals.isEmpty && stats == nil:
            LoadingView(label: "Loading your workspace…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        default:
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    pageHeader
                    metricGrid
                    if isSuperAdmin, let aiCost, aiCost.configured {
                        aiSpendWidget(aiCost)
                    }
                    if !proposals.isEmpty {
                        recentDocsWidget
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let user = model.auth.currentUser {
                let first = user.displayName.components(separatedBy: " ").first ?? user.displayName
                (Text(first).font(.system(size: 34, weight: .regular, design: .serif))
                    + Text(" · Foundry HQ")
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .foregroundStyle(.secondary))
            }
            Text(Date(), format: Date.FormatStyle().weekday(.wide).month(.wide).day())
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Metric widgets

    private var metricGrid: some View {
        LazyVGrid(columns: twoCol, spacing: 14) {
            FoundryCard(index: 1, title: "Proposals") {
                StatDisplay(value: "\(proposals.count)", label: "Total")
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            FoundryCard(index: 2, title: "Clients") {
                StatDisplay(
                    value: clientsCount.map(String.init) ?? "—",
                    label: "Active"
                )
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            FoundryCard(index: 3, title: "Candidates") {
                StatDisplay(
                    value: stats.map { "\($0.total)" } ?? "—",
                    label: "In pipeline"
                )
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            FoundryCard(index: 4, title: "Recheck Due") {
                let due = stats?.recheckDue ?? 0
                StatDisplay(
                    value: "\(due)",
                    label: "Flagged",
                    tint: due > 0 ? .red : .primary
                )
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - AI Spend widget

    private func aiSpendWidget(_ cost: AiCostSummary) -> some View {
        let currency = cost.commonCurrency ?? "USD"
        let okProviders = cost.providers.filter { $0.status == .ok }

        return FoundryCard(
            index: 5,
            title: "AI Spend",
            trailing: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.foundryPurple)
                    Text("SUPER ADMIN")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(.tertiary)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 28) {
                    StatDisplay(
                        value: Formatters.currency(cost.totalMonthToDate, code: currency),
                        label: "This month",
                        size: 36
                    )
                    StatDisplay(
                        value: Formatters.currency(cost.totalToday, code: currency),
                        label: "Today",
                        size: 26
                    )
                    Spacer()
                }
                .padding(14)

                if okProviders.count > 1 {
                    FoundryDivider()
                    VStack(spacing: 0) {
                        ForEach(Array(okProviders.enumerated()), id: \.element.id) { idx, provider in
                            HStack {
                                Text(provider.providerLabel)
                                    .font(.callout)
                                if let m = provider.modelLabel, !m.isEmpty {
                                    Text(m)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Text(Formatters.currency(provider.monthToDate, code: provider.currency))
                                    .font(.system(size: 13, design: .monospaced))
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            if idx < okProviders.count - 1 {
                                FoundryDivider().padding(.horizontal, 14)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recent Docs widget

    private var recentDocsWidget: some View {
        let recent = Array(proposals.prefix(8))
        let cardIndex = isSuperAdmin && (aiCost?.configured ?? false) ? 6 : 5

        return FoundryCard(index: cardIndex, title: "Recent Docs") {
            VStack(spacing: 0) {
                ForEach(Array(recent.enumerated()), id: \.element.id) { idx, item in
                    NavigationLink(value: ProposalRoute(id: item.id)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if let client = item.clientName, !client.isEmpty {
                                    Text(client)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            StatusChip(text: item.status.label, tint: item.status.tint)
                            Text(Formatters.relative(item.updatedAt))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(width: 56, alignment: .trailing)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                    }
                    .buttonStyle(.plain)

                    if idx < recent.count - 1 {
                        FoundryDivider().padding(.horizontal, 14)
                    }
                }
            }
        }
    }

    // MARK: - Load

    private func load() async {
        if proposals.isEmpty && stats == nil { state = .loading }
        do {
            async let proposalsTask = model.api.listProposals(sort: "updatedAt:desc")
            async let clientsTask: [ClientListItem]? = try? model.api.listClients()
            async let statsTask: CodeClearStats? = try? model.api.codeClearStats()

            proposals = try await proposalsTask
            clientsCount = (await clientsTask)?.count
            stats = await statsTask
            state = .loaded(())
            model.lastRefresh = Date()
        } catch {
            state = .failed(error.userMessage)
        }
        // AI spend — super-admin only, best-effort, never affects main dashboard state.
        if isSuperAdmin {
            aiCost = try? await model.api.aiCost()
            if let aiCost, aiCost.configured {
                AppGroupStore.update { snapshot in
                    snapshot.aiSpend = .init(
                        today: aiCost.totalToday,
                        monthToDate: aiCost.totalMonthToDate,
                        currency: aiCost.commonCurrency ?? "USD"
                    )
                }
            }
        }
    }
}
