import SwiftUI

/// Native scan detail: header (health + status), AI analysis essentials, and checks grouped by
/// category. While the scan is running it consumes the SSE stream and merges delta checks + scalar
/// state live. The full visual report (discovery kit, deploy/code/browser insights, competitors)
/// opens in the WebKit pane.
struct PulseDetailView: View {
    @Environment(AppModel.self) private var model
    let id: String

    @State private var scan: PulseScanDetail?
    @State private var state: LoadState<Void> = .idle
    @State private var liveChecks: [String: PulseScanCheck] = [:]
    @State private var liveStatus: PulseScanStatus?
    @State private var liveHealth: Int?
    @State private var streamTask: Task<Void, Never>?
    @State private var busy = false
    @State private var actionError: String?

    var body: some View {
        content
            .navigationTitle(scan?.projectName ?? "Scan")
            .navigationSubtitle(displayStatus.label + (displayHealth.map { " · Health \($0)" } ?? ""))
            .toolbar { toolbar }
            .task { await load() }
            .onDisappear { streamTask?.cancel() }
    }

    // MARK: Derived

    private var displayStatus: PulseScanStatus { liveStatus ?? scan?.status ?? .unknown }
    private var displayHealth: Int? { liveHealth ?? scan?.healthScore }
    private var scanTarget: String? { scan?.inputUrl ?? scan?.inputGithubRepo ?? scan?.inputDescription }

    private var mergedChecks: [PulseScanCheck] {
        var byId: [String: PulseScanCheck] = [:]
        for check in scan?.checks ?? [] { byId[check.id] = check }
        for (key, value) in liveChecks { byId[key] = value }
        return byId.values.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var groupedChecks: [(category: String, checks: [PulseScanCheck])] {
        let groups = Dictionary(grouping: mergedChecks, by: { $0.category })
        return groups.keys.sorted().map { ($0, groups[$0]!.sorted { $0.sortOrder < $1.sortOrder }) }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading where scan == nil:
            LoadingView(label: "Loading scan…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        default:
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let actionError { Text(actionError).font(.callout).foregroundStyle(.red) }
                    if displayStatus.isRunning { runningBanner }
                    if let analysis = scan?.llmAnalysis { analysisSection(analysis) }
                    if let browser = scan?.browserInsights { BrowserInsightsSection(insights: browser) }
                    if let code = scan?.codeInsights { CodeInsightsSection(insights: code) }
                    if let deploy = scan?.deployInsights { DeployInsightsSection(insights: deploy) }
                    if let analysis = scan?.llmAnalysis {
                        if (analysis.buildOpportunities?.isEmpty == false)
                            || (analysis.scalingRoadmap?.isEmpty == false)
                            || (analysis.techDebt?.isEmpty == false) {
                            OpportunitiesSection(analysis: analysis)
                        }
                        if (analysis.productionBlockers?.isEmpty == false)
                            || (analysis.productionReadinessChecklist?.isEmpty == false)
                            || analysis.techStackAnalysis != nil {
                            ReadinessSection(analysis: analysis)
                        }
                    }
                    if let kit = scan?.discoveryKit { DiscoveryKitSection(kit: kit) }
                    if let competitors = scan?.competitorData, competitors.scans?.isEmpty == false {
                        CompetitorsSection(data: competitors, ownScore: displayHealth)
                    }
                    if !mergedChecks.isEmpty { checksSection }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            HealthBadge(score: displayHealth, status: displayStatus, size: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text(scan?.projectName ?? "—").font(.title2.weight(.semibold))
                if let scanTarget {
                    Text(scanTarget).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
                }
                HStack(spacing: 8) {
                    StatusChip(text: displayStatus.label, tint: displayStatus.tint)
                    if let stack = scan?.techStack, !stack.isEmpty {
                        Text(stack.prefix(6).joined(separator: " · "))
                            .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }
            Spacer()
        }
    }

    private var runningBanner: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Scan running — checks appear live as they complete.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func analysisSection(_ analysis: PulseAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary = analysis.executiveSummary, !summary.isEmpty {
                SectionHeader("Executive summary")
                Text(summary).font(.callout)
            }
            if let strengths = analysis.strengths, !strengths.isEmpty {
                SectionHeader("Strengths")
                ForEach(strengths) { strength in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(strength.title).font(.callout.weight(.medium))
                            Text(strength.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    }
                }
            }
            if let gaps = analysis.criticalGaps, !gaps.isEmpty {
                SectionHeader("Critical gaps")
                ForEach(gaps) { gap in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gap.gap).font(.callout.weight(.medium))
                            Text(gap.impact).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var checksSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Checks (\(mergedChecks.count))")
            ForEach(groupedChecks, id: \.category) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.category.uppercased())
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    ForEach(group.checks) { PulseCheckRow(check: $0) }
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Button {
                model.openWeb(path: "app/pulse/\(id)")
            } label: {
                Label("Open in Foundry Web", systemImage: "safari")
            }
            .help("Open this scan in the browser")
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                if displayStatus == .completed {
                    Button { runAction { try await model.api.reanalysePulseScan(id: id) } } label: {
                        Label("Re-analyse", systemImage: "sparkles")
                    }
                }
                if displayStatus == .failed {
                    Button { runAction { try await model.api.retryPulseScan(id: id) } } label: {
                        Label("Retry scan", systemImage: "arrow.clockwise")
                    }
                }
                if displayStatus.isRunning {
                    Button(role: .destructive) { runAction { try await model.api.cancelPulseScan(id: id) } } label: {
                        Label("Cancel scan", systemImage: "stop.circle")
                    }
                }
                Divider()
                Button { Task { await load() } } label: { Label("Reload", systemImage: "arrow.clockwise") }
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
            .disabled(busy)
        }
    }

    // MARK: Data

    private func load() async {
        if scan == nil { state = .loading }
        do {
            let detail = try await model.api.getPulseScan(id: id)
            scan = detail
            liveStatus = detail.status
            liveHealth = detail.healthScore
            liveChecks = [:]
            state = .loaded(())
            if !detail.status.isTerminal { startStreaming() }
        } catch {
            state = .failed(error.userMessage)
        }
    }

    private func startStreaming() {
        streamTask?.cancel()
        streamTask = Task { @MainActor in
            do {
                let stream = try model.api.pulseScanStream(id: id)
                for try await payload in stream {
                    guard let data = payload.data(using: .utf8),
                          let envelope = try? JSONDecoder.foundry.decode(PulseStreamEnvelope.self, from: data)
                    else { continue }
                    apply(envelope)
                    if envelope.type == "complete" { break }
                }
            } catch {
                // Stream dropped — the reload below recovers final state.
            }
            await load()
        }
    }

    private func apply(_ envelope: PulseStreamEnvelope) {
        switch envelope.type {
        case "checks":
            for check in envelope.checks ?? [] { liveChecks[check.id] = check }
        case "meta":
            if let status = envelope.scan?.status { liveStatus = status }
            if let health = envelope.scan?.healthScore { liveHealth = health }
        default:
            break
        }
    }

    private func runAction(_ work: @escaping () async throws -> Void) {
        Task {
            busy = true
            actionError = nil
            defer { busy = false }
            do {
                try await work()
                await load()
            } catch {
                actionError = error.userMessage
            }
        }
    }
}

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View { Text(title).font(.headline) }
}

private struct PulseCheckRow: View {
    let check: PulseScanCheck

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: check.status.systemImage)
                .foregroundStyle(check.status.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.label).font(.callout)
                if let detail = check.detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
