import SwiftUI

/// Navigation value for the scan list → detail push.
struct PulseScanRoute: Hashable { let id: String }

/// Pulse: a segmented container over Scans · Monitors · Leads. Scans are native (list + live
/// detail); the full visual report opens in the WebKit pane from the detail screen.
struct PulseView: View {
    @Environment(AppModel.self) private var model

    enum Segment: String, CaseIterable, Identifiable {
        case scans = "Scans", monitors = "Monitors", leads = "Leads"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .scans
    @State private var scans: [PulseScanSummary] = []
    @State private var state: LoadState<Void> = .idle
    @State private var search = ""
    @State private var showingCreate = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        Group {
            switch segment {
            case .scans: scansContent
            case .monitors: PulseMonitorsView()
            case .leads: PulseLeadsView()
            }
        }
        .navigationTitle("Pulse")
        .searchable(text: $search, prompt: "Search scans")
        .searchFocused($searchFocused)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $segment) {
                    ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingCreate = true } label: { Label("New Scan", systemImage: "plus") }
                    .help("New Pulse scan")
            }
        }
        .task(id: segment) { if segment == .scans { await load() } }
        .onChange(of: model.refreshToken) { if segment == .scans { Task { await load() } } }
        .onChange(of: model.searchToken) { searchFocused = true }
        .navigationDestination(for: PulseScanRoute.self) { PulseDetailView(id: $0.id) }
        .sheet(isPresented: $showingCreate) {
            CreateScanSheet { _ in
                showingCreate = false
                segment = .scans
                Task { await load() }
            }
        }
    }

    private var filteredScans: [PulseScanSummary] {
        let sorted = scans.sorted { $0.createdAt > $1.createdAt }
        guard let q = search.nilIfEmpty?.lowercased() else { return sorted }
        return sorted.filter { $0.projectName.lowercased().contains(q) || $0.target.lowercased().contains(q) }
    }

    @ViewBuilder private var scansContent: some View {
        switch state {
        case .idle, .loading where scans.isEmpty:
            LoadingView(label: "Loading scans…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        default:
            let items = filteredScans
            if items.isEmpty {
                ContentUnavailableView {
                    Label("No scans", systemImage: "waveform.path.ecg")
                } description: {
                    Text(search.isEmpty ? "Run a Pulse scan on a website or GitHub repo." : "No results for “\(search)”.")
                } actions: {
                    Button("New Scan") { showingCreate = true }.buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(items) { scan in
                        NavigationLink(value: PulseScanRoute(id: scan.id)) { PulseScanRow(scan: scan) }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func load() async {
        if scans.isEmpty { state = .loading }
        do {
            scans = try await model.api.listPulseScans()
            state = .loaded(())
            model.lastRefresh = Date()
            // Feed the Pulse Health widget (best-effort).
            let recent = scans.sorted { $0.createdAt > $1.createdAt }.prefix(6)
            AppGroupStore.update { snapshot in
                snapshot.scans = recent.map { .init(id: $0.id, name: $0.projectName, score: $0.healthScore) }
            }
        } catch {
            state = .failed(error.userMessage)
        }
    }
}

private struct PulseScanRow: View {
    let scan: PulseScanSummary

    var body: some View {
        HStack(spacing: 14) {
            HealthBadge(score: scan.healthScore, status: scan.status)
            VStack(alignment: .leading, spacing: 4) {
                Text(scan.projectName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(scan.target)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                StatusChip(text: scan.status.label, tint: scan.status.tint)
                Text(Formatters.relative(scan.createdAt))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}

/// Health-score badge — editorial rounded-rect with large serif number, colored by band.
/// Replaces the old filled circle; reused by scans, monitors, and leads.
struct HealthBadge: View {
    let score: Int?
    var status: PulseScanStatus = .completed
    var size: CGFloat = 40

    var tint: Color { score.map { Color.pulseHealth($0) } ?? .secondary }

    var body: some View {
        ZStack {
            if status.isRunning {
                ProgressView().controlSize(.small)
            } else if let score {
                Text("\(score)")
                    .font(.system(size: size * 0.5, weight: .semibold, design: .serif))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.system(size: size * 0.38, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(tint.opacity(0.2), lineWidth: 0.75)
        )
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if status.isRunning { return "Scan running" }
        if let score { return "Health score \(score)" }
        return "No health score"
    }
}
