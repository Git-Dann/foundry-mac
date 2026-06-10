import SwiftUI

/// Navigation value for the study list → detail push.
struct StudyRoute: Hashable { let id: String }

/// Study — AI-powered user research, fully native (was the last WebKit sidebar embed).
struct StudyView: View {
    @Environment(AppModel.self) private var model

    @State private var studies: [StudyListItem] = []
    @State private var state: LoadState<Void> = .idle
    @State private var search = ""
    @State private var showingCreate = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        content
            .navigationTitle("Study")
            .searchable(text: $search, prompt: "Search studies")
            .searchFocused($searchFocused)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingCreate = true } label: { Label("New Study", systemImage: "plus") }
                        .help("New research study")
                }
            }
            .task { await load() }
            .onChange(of: model.refreshToken) { Task { await load() } }
            .onChange(of: model.searchToken) { searchFocused = true }
            .navigationDestination(for: StudyRoute.self) { StudyDetailView(id: $0.id) }
            .sheet(isPresented: $showingCreate) {
                CreateStudySheet { Task { await load() } }
            }
    }

    private var filtered: [StudyListItem] {
        let sorted = studies.sorted { $0.updatedAt > $1.updatedAt }
        guard let q = search.nilIfEmpty?.lowercased() else { return sorted }
        return sorted.filter {
            $0.title.lowercased().contains(q) || $0.problemStatement.lowercased().contains(q)
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading where studies.isEmpty:
            LoadingView(label: "Loading studies…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        default:
            let items = filtered
            if items.isEmpty {
                ContentUnavailableView {
                    Label("No studies", systemImage: "graduationcap")
                } description: {
                    Text(search.isEmpty
                         ? "Run AI persona interviews against a problem statement."
                         : "No results for “\(search)”.")
                } actions: {
                    Button("New Study") { showingCreate = true }.buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(items) { study in
                        NavigationLink(value: StudyRoute(id: study.id)) { StudyRow(study: study) }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func load() async {
        if studies.isEmpty { state = .loading }
        do {
            studies = try await model.api.listStudies()
            state = .loaded(())
            model.lastRefresh = Date()
        } catch {
            state = .failed(error.userMessage)
        }
    }
}

private struct StudyRow: View {
    let study: StudyListItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(study.title).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(study.selectedPersonaIds.count) persona\(study.selectedPersonaIds.count == 1 ? "" : "s")")
                    if study.sessionCount > 0 { Text("· \(study.completedSessionCount)/\(study.sessionCount) sessions") }
                    if let client = study.workspaceClientName { Text("· \(client)") }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if study.status.isActive { ProgressView().controlSize(.small) }
            StatusChip(text: study.status.label, tint: study.status.tint)
            Text(Formatters.relative(study.updatedAt))
                .font(.caption).foregroundStyle(.tertiary).frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }
}

/// Create a study: problem statement, goals, mode, and persona selection.
struct CreateStudySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onCreated: () -> Void

    @State private var title = ""
    @State private var problem = ""
    @State private var goals = ""
    @State private var sessionMode = "ONE_ON_ONE"
    @State private var personas: [StudyPersona] = []
    @State private var selected: Set<String> = []
    @State private var submitting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New study").font(.title3.weight(.semibold))
            Form {
                TextField("Title", text: $title)
                TextField("Problem statement", text: $problem, axis: .vertical).lineLimit(2...4)
                TextField("Research goals (one per line)", text: $goals, axis: .vertical).lineLimit(2...4)
                Picker("Mode", selection: $sessionMode) {
                    Text("1-on-1 interviews").tag("ONE_ON_ONE")
                    Text("Group session").tag("GROUP")
                }
            }
            .formStyle(.columns)

            VStack(alignment: .leading, spacing: 6) {
                Text("Personas").font(.caption).foregroundStyle(.secondary)
                if personas.isEmpty {
                    ProgressView().controlSize(.small)
                } else {
                    FlowingChips(personas: personas, selected: $selected)
                }
            }

            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button { Task { await submit() } } label: {
                    if submitting { ProgressView().controlSize(.small) } else { Text("Create study") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmed.isEmpty || problem.trimmed.isEmpty || selected.isEmpty || submitting)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task { personas = (try? await model.api.listStudyPersonas()) ?? [] }
    }

    private func submit() async {
        submitting = true
        error = nil
        defer { submitting = false }
        let input = StudyCreateInput(
            title: title.trimmed,
            problemStatement: problem.trimmed,
            researchGoals: goals.split(separator: "\n").map { String($0).trimmed }.filter { !$0.isEmpty },
            sessionMode: sessionMode,
            selectedPersonaIds: Array(selected)
        )
        do {
            _ = try await model.api.createStudy(input)
            onCreated()
            dismiss()
        } catch {
            self.error = error.userMessage
        }
    }
}

/// Togglable persona chips (wrapping rows of 4).
private struct FlowingChips: View {
    let personas: [StudyPersona]
    @Binding var selected: Set<String>

    var body: some View {
        let rows = stride(from: 0, to: personas.count, by: 4).map { Array(personas[$0..<min($0 + 4, personas.count)]) }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { persona in
                        PersonaChip(persona: persona, isSelected: selected.contains(persona.id)) {
                            if selected.contains(persona.id) { selected.remove(persona.id) } else { selected.insert(persona.id) }
                        }
                    }
                }
            }
        }
    }
}

struct PersonaChip: View {
    let persona: StudyPersona
    var isSelected = false
    var action: (() -> Void)?

    var body: some View {
        Button { action?() } label: {
            HStack(spacing: 5) {
                Circle().fill(Color.persona(persona.color)).frame(width: 7, height: 7)
                Text(persona.shortName ?? persona.name).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(
                isSelected ? Color.persona(persona.color).opacity(0.18) : Color.secondary.opacity(0.08),
                in: Capsule()
            )
            .overlay(Capsule().stroke(isSelected ? Color.persona(persona.color).opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(persona.description ?? persona.name)
    }
}
