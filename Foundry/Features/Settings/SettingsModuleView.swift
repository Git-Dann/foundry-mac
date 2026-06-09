import SwiftUI

/// Workspace Settings (distinct from the app's ⌘, preferences): AI providers + Team. Admin-only
/// surfaces fail gracefully for non-admins. Onboarding-form builder / agent toggles stay in Web.
struct SettingsModuleView: View {
    @Environment(AppModel.self) private var model

    enum Tab: String, CaseIterable, Identifiable {
        case ai = "AI providers", team = "Team"
        var id: String { rawValue }
    }
    @State private var tab: Tab = .ai

    var body: some View {
        Group {
            switch tab {
            case .ai: AIProvidersView()
            case .team: TeamView()
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) { ForEach(Tab.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).fixedSize()
            }
        }
    }
}

// MARK: - AI providers

private struct AIProvidersView: View {
    @Environment(AppModel.self) private var model

    @State private var integrations: SettingsIntegrations?
    @State private var state: LoadState<Void> = .idle
    @State private var provider: AIProvider = .anthropic
    @State private var newKey = ""
    @State private var modelName = ""
    @State private var localUrl = ""
    @State private var saving = false
    @State private var error: String?
    @State private var saved = false

    var body: some View {
        content
            .task { await load() }
            .onChange(of: model.refreshToken) { Task { await load() } }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading:
            LoadingView(label: "Loading settings…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        case .loaded:
            Form {
                Section("Active provider") {
                    Picker("Provider", selection: $provider) {
                        ForEach(AIProvider.allCases) { Text($0.label).tag($0) }
                    }
                    .onChange(of: provider) { syncFields() }
                }

                Section(provider.label) {
                    if provider == .local {
                        TextField("Base URL", text: $localUrl)
                        TextField("Model", text: $modelName)
                    } else {
                        LabeledContent("API key") {
                            Text(maskedKey ?? "Not set").foregroundStyle(.secondary)
                        }
                        if let source = keySource { LabeledContent("Source", value: source == "env" ? "Environment" : "Workspace") }
                        SecureField("Set a new key (blank = keep)", text: $newKey)
                        TextField("Model", text: $modelName)
                    }
                }

                if saved { Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView().controlSize(.small) } else { Text("Save") }
                    }
                    .disabled(saving)
                }
            }
        }
    }

    private var maskedKey: String? {
        switch provider {
        case .anthropic: return integrations?.anthropicKeyMasked
        case .openai: return integrations?.openaiKeyMasked
        case .gemini: return integrations?.geminiKeyMasked
        case .local: return nil
        }
    }

    private var keySource: String? {
        switch provider {
        case .anthropic: return integrations?.anthropicKeySource
        case .openai: return integrations?.openaiKeySource
        case .gemini: return integrations?.geminiKeySource
        case .local: return nil
        }
    }

    private func syncFields() {
        guard let i = integrations else { return }
        newKey = ""
        saved = false
        switch provider {
        case .anthropic: modelName = i.anthropicModel ?? ""
        case .openai: modelName = i.openaiModel ?? ""
        case .gemini: modelName = i.geminiModel ?? ""
        case .local: modelName = i.localLlmModel ?? ""; localUrl = i.localLlmUrl ?? ""
        }
    }

    private func load() async {
        state = .loading
        do {
            let result = try await model.api.settingsIntegrations()
            integrations = result
            provider = AIProvider(rawValue: result.aiProvider) ?? .anthropic
            syncFields()
            state = .loaded(())
        } catch {
            state = .failed(error.userMessage)
        }
    }

    private func save() async {
        saving = true; error = nil; saved = false
        defer { saving = false }
        var update = IntegrationsUpdate()
        update.aiProvider = provider.rawValue
        let key = newKey.trimmed.nilIfEmpty
        let modelValue = modelName.trimmed.nilIfEmpty
        switch provider {
        case .anthropic: update.anthropicApiKey = key; update.anthropicModel = modelValue
        case .openai: update.openaiApiKey = key; update.openaiModel = modelValue
        case .gemini: update.geminiApiKey = key; update.geminiModel = modelValue
        case .local: update.localLlmUrl = localUrl.trimmed.nilIfEmpty; update.localLlmModel = modelValue
        }
        do {
            try await model.api.updateIntegrations(update)
            saved = true
            await load()
        } catch {
            self.error = error.userMessage
        }
    }
}

// MARK: - Team

private struct TeamView: View {
    @Environment(AppModel.self) private var model

    @State private var members: [WorkspaceMember] = []
    @State private var state: LoadState<Void> = .idle

    private let roles = ["DEVELOPER", "STAFF", "ADMIN", "SUPER_ADMIN"]
    private var isAdmin: Bool { ["ADMIN", "SUPER_ADMIN"].contains(model.auth.currentUser?.role) }

    var body: some View {
        content
            .task { await load() }
            .onChange(of: model.refreshToken) { Task { await load() } }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading where members.isEmpty:
            LoadingView(label: "Loading team…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        default:
            List {
                Section("Members (\(members.count))") {
                    ForEach(members) { member in
                        HStack(spacing: 10) {
                            InitialsAvatar(name: member.displayName, url: nil, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.displayName).fontWeight(.medium)
                                Text(member.user.email).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isAdmin {
                                Menu {
                                    ForEach(roles, id: \.self) { role in
                                        Button(roleLabel(role)) { Task { await setRole(member, role) } }
                                    }
                                } label: {
                                    StatusChip(text: member.roleLabel, tint: .blue)
                                }
                                .menuStyle(.borderlessButton).fixedSize()
                            } else {
                                StatusChip(text: member.roleLabel, tint: .blue)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func roleLabel(_ role: String) -> String {
        switch role {
        case "SUPER_ADMIN": return "Super Admin"
        case "ADMIN": return "Admin"
        case "STAFF": return "Staff"
        case "DEVELOPER": return "Developer"
        default: return role.capitalized
        }
    }

    private func load() async {
        if members.isEmpty { state = .loading }
        do { members = try await model.api.listTeamMembers(); state = .loaded(()) }
        catch { state = .failed(error.userMessage) }
    }

    private func setRole(_ member: WorkspaceMember, _ role: String) async {
        guard role != member.role else { return }
        _ = try? await model.api.updateMemberRole(memberId: member.id, role: role)
        await load()
    }
}
