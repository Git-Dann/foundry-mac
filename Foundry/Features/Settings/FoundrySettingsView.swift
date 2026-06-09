import SwiftUI

/// Native Settings scene: Account · API · Updates · Advanced.
/// (The Updates tab's Sparkle controls are wired in the Updates phase.)
struct FoundrySettingsView: View {
    var body: some View {
        TabView {
            AccountSettingsTab()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            APISettingsTab()
                .tabItem { Label("API", systemImage: "network") }
            UpdatesSettingsTab()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
            AdvancedSettingsTab()
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }
        .frame(width: 600, height: 460)
    }
}

private struct AccountSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            if let user = model.auth.currentUser {
                LabeledContent("Signed in as", value: user.displayName)
                LabeledContent("Email", value: user.email)
                LabeledContent("Role", value: user.roleLabel)
                Section {
                    Button("Sign Out", role: .destructive) { model.auth.signOut() }
                }
            } else {
                ContentUnavailableView {
                    Label("Not signed in", systemImage: "person.crop.circle.badge.exclamationmark")
                } actions: {
                    Button("Sign in to Foundry") { model.signIn() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct APISettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var overrideText = ""
    @State private var healthResult: String?
    @State private var checking = false

    var body: some View {
        Form {
            Section("Server") {
                LabeledContent("Current base URL", value: model.environment.baseURL.absoluteString)
                LabeledContent("Mode", value: model.environment.isUsingProductionURL ? "Production" : "Override")
            }
            Section("Developer override") {
                TextField("https://preview.example.com", text: $overrideText)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Apply") {
                        model.environment.setBaseURLOverride(overrideText)
                        healthResult = nil
                    }
                    Button("Reset to production") {
                        model.environment.setBaseURLOverride(nil)
                        overrideText = ""
                        healthResult = nil
                    }
                }
                Text("Point the app at a non-production deployment. No secrets are stored.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Connection") {
                Button {
                    checkHealth()
                } label: {
                    if checking { ProgressView().controlSize(.small) } else { Text("Check connection") }
                }
                .disabled(checking)
                if let healthResult {
                    Text(healthResult).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if !model.environment.isUsingProductionURL {
                overrideText = model.environment.baseURL.absoluteString
            }
        }
    }

    private func checkHealth() {
        checking = true
        healthResult = nil
        Task {
            defer { checking = false }
            do {
                let health = try await model.api.health()
                healthResult = "✓ \(health.service) is healthy" + (health.version.map { " (v\($0))" } ?? "")
            } catch {
                healthResult = "✕ " + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }
}

/// Updates tab — Sparkle controls.
struct UpdatesSettingsTab: View {
    @Environment(AppModel.self) private var model
    @Environment(UpdateController.self) private var updates

    var body: some View {
        @Bindable var updates = updates
        Form {
            Section("Software updates") {
                Toggle("Automatically check for updates", isOn: $updates.automaticallyChecksForUpdates)
                LabeledContent("Current version", value: "\(model.environment.appVersion) (\(model.environment.buildNumber))")
                LabeledContent("Last checked", value: updates.lastUpdateCheckDescription)
                Button("Check for Updates…") { updates.checkForUpdates() }
                    .disabled(!updates.canCheckForUpdates)
            }
            Section("Update feed") {
                Text(updates.feedURLString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Section {
                Text("Foundry updates itself in-place via Sparkle — you install once from the DMG, then future versions arrive inside the app, EdDSA-signed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("About") {
                LabeledContent("Version", value: model.environment.appVersion)
                LabeledContent("Build", value: model.environment.buildNumber)
                LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "—")
            }
            Section {
                Button("Open Foundry Web") { model.openWeb() }
                Button("Sign Out", role: .destructive) { model.auth.signOut() }
            }
        }
        .formStyle(.grouped)
    }
}
