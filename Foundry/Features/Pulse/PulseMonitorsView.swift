import SwiftUI

/// Continuous GitHub/URL monitors — list, create, pause/resume, delete.
struct PulseMonitorsView: View {
    @Environment(AppModel.self) private var model
    @State private var state: LoadState<[PulseMonitor]> = .idle
    @State private var showingCreate = false
    @State private var busyId: String?

    var body: some View {
        content
            .task { await load() }
            .onChange(of: model.refreshToken) { Task { await load() } }
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    Button { showingCreate = true } label: { Label("New Monitor", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $showingCreate) {
                CreateMonitorSheet { showingCreate = false; Task { await load() } }
            }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading:
            LoadingView(label: "Loading monitors…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        case .loaded(let monitors):
            if monitors.isEmpty {
                ContentUnavailableView {
                    Label("No monitors", systemImage: "bell.badge")
                } description: {
                    Text("Watch a repo or URL continuously and get alerted when its health drops.")
                } actions: {
                    Button("New Monitor") { showingCreate = true }.buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(monitors) { monitor in
                        MonitorRow(
                            monitor: monitor,
                            busy: busyId == monitor.id,
                            toggle: { await setActive(monitor, !monitor.isActive) },
                            delete: { await remove(monitor) }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await model.api.listPulseMonitors())
            model.lastRefresh = Date()
        } catch {
            state = .failed(error.userMessage)
        }
    }

    private func setActive(_ monitor: PulseMonitor, _ active: Bool) async {
        busyId = monitor.id
        defer { busyId = nil }
        try? await model.api.setPulseMonitorActive(id: monitor.id, isActive: active)
        await load()
    }

    private func remove(_ monitor: PulseMonitor) async {
        busyId = monitor.id
        defer { busyId = nil }
        try? await model.api.deletePulseMonitor(id: monitor.id)
        await load()
    }
}

private struct MonitorRow: View {
    let monitor: PulseMonitor
    let busy: Bool
    let toggle: () async -> Void
    let delete: () async -> Void
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 12) {
            HealthBadge(score: monitor.lastHealthScore)
            VStack(alignment: .leading, spacing: 3) {
                Text(monitor.projectName).font(.body.weight(.medium)).lineLimit(1)
                Text(monitor.target).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            StatusChip(text: monitor.isActive ? "Active" : "Paused", tint: monitor.isActive ? .green : .secondary)
            Menu {
                Button(monitor.isActive ? "Pause" : "Resume") { Task { await toggle() } }
                Button(confirmDelete ? "Tap again to delete" : "Delete", role: .destructive) {
                    if confirmDelete { Task { await delete() } } else { confirmDelete = true }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(busy)
        }
        .padding(.vertical, 3)
    }
}

/// Create a continuous monitor for a repo or URL.
struct CreateMonitorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onCreated: () -> Void

    @State private var projectName = ""
    @State private var inputType: PulseInputType = .githubRepo
    @State private var inputUrl = ""
    @State private var inputRepo = ""
    @State private var threshold = 10.0
    @State private var submitting = false
    @State private var error: String?

    private var canSubmit: Bool {
        !projectName.trimmed.isEmpty &&
        (inputType == .githubRepo ? !inputRepo.trimmed.isEmpty : !inputUrl.trimmed.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New monitor").font(.title3.weight(.semibold))
            Form {
                TextField("Project name", text: $projectName)
                Picker("Watch", selection: $inputType) {
                    Text("GitHub repo").tag(PulseInputType.githubRepo)
                    Text("Website").tag(PulseInputType.url)
                }
                if inputType == .githubRepo {
                    TextField("owner/repo", text: $inputRepo)
                } else {
                    TextField("https://example.com", text: $inputUrl)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Alert when health drops by \(Int(threshold))")
                    Slider(value: $threshold, in: 1...50, step: 1)
                }
            }
            .formStyle(.columns)
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button { Task { await submit() } } label: {
                    if submitting { ProgressView().controlSize(.small) } else { Text("Create") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || submitting)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func submit() async {
        submitting = true
        error = nil
        defer { submitting = false }
        let input = PulseMonitorInput(
            projectName: projectName.trimmed,
            inputType: inputType,
            inputUrl: inputType == .url ? inputUrl.trimmed.nilIfEmpty : nil,
            inputGithubRepo: inputType == .githubRepo ? inputRepo.trimmed.nilIfEmpty : nil,
            alertThreshold: Int(threshold)
        )
        do {
            _ = try await model.api.createPulseMonitor(input)
            onCreated()
        } catch {
            self.error = error.userMessage
        }
    }
}
