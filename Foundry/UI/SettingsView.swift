import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Sources", systemImage: "tray.2") { SourcesSettings() }
            Tab("Advanced", systemImage: "wrench.and.screwdriver") { AdvancedSettings() }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(UpdateController.self) private var updates
    @AppStorage(NotificationPreferences.digestEnabledKey) private var digest = true
    @AppStorage(NotificationPreferences.digestTimeKey) private var digestMinutes = 9 * 60
    @AppStorage(NotificationPreferences.overdueEnabledKey) private var overdue = true
    @AppStorage(GlobalHotKey.enabledKey) private var hotkey = true

    var body: some View {
        @Bindable var updates = updates
        Form {
            Section("Account") {
                if let user = model.auth.currentUser {
                    LabeledContent("Signed in as") { Text(user.email).textSelection(.enabled) }
                    Button("Sign Out") { model.signOut() }
                } else {
                    SignInPrompt(compact: true)
                }
            }
            Section {
                Toggle("Morning digest", isOn: $digest)
                if digest {
                    DatePicker("At", selection: digestTime, displayedComponents: .hourAndMinute)
                }
                Toggle("Tell me when something becomes overdue", isOn: $overdue)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Foundry never notifies you about a new suggestion. A quiet morning sends nothing.")
                    .foregroundStyle(.secondary)
            }
            Section("Quick add") {
                Toggle("Open quick add with \(GlobalHotKey.Combo.quickAdd.label)", isOn: $hotkey)
                Text("Also in Spotlight and Shortcuts as “Add To-do”.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $updates.automaticallyChecksForUpdates)
                LabeledContent("Last checked", value: updates.lastUpdateCheckDescription)
                Button("Check Now") { updates.checkForUpdates() }.disabled(!updates.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
        .onChange(of: digest) { reschedule() }
        .onChange(of: digestMinutes) { reschedule() }
        .onChange(of: overdue) { reschedule() }
        .onChange(of: hotkey) { _, on in FoundryApp.applyHotKey(on) }
    }

    private var digestTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: digestMinutes / 60, minute: digestMinutes % 60, second: 0, of: Date()) ?? Date()
        } set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            digestMinutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
        }
    }

    private func reschedule() { model.notifications.reschedule(items: model.store.items) }
}

private struct SourcesSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                ForEach(CommitmentSettings.Toggle.offered) { source in
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: binding(source)) {
                            Label(source.title, systemImage: source.symbol)
                        }
                        Text(source.detail).font(.callout).foregroundStyle(.secondary)
                        if let problem = model.store.settings.problem(for: source) {
                            Label(problem, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if source == .slack, model.store.settings.slackEnabled, !model.store.settings.slackConnected {
                            Text("Your Foundry email isn't linked to a Slack account yet.")
                                .font(.callout).foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Where Foundry looks for promises")
            } footer: {
                Text("Suggestions wait for you to add them. Only the promise and a short quote are kept, never the whole message. Foundry never sends, replies or books anything.")
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    if let at = model.store.settings.lastSyncedAt {
                        Text("Last read \(at.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary)
                    } else {
                        Text("Not read yet").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.store.isCheckingSources { ProgressView().controlSize(.small) }
                    Button("Check Now") { Task { await model.store.checkSources() } }
                        .disabled(model.store.isCheckingSources || !model.auth.isSignedIn)
                }
                if let summary = model.store.lastCheckSummary {
                    Text(summary).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(!model.auth.isSignedIn)
        .task { model.refreshIfStale() }
    }

    private func binding(_ source: CommitmentSettings.Toggle) -> Binding<Bool> {
        Binding {
            model.store.settings.isOn(source)
        } set: { on in
            var s = model.store.settings
            s.set(source, on)
            Task { await model.store.updateSettings(s) }
        }
    }
}

private struct AdvancedSettings: View {
    @Environment(AppModel.self) private var model
    @State private var override = UserDefaults.standard.string(forKey: AppEnvironment.baseURLOverrideKey) ?? ""
    @State private var rejected = false

    var body: some View {
        Form {
            Section {
                TextField("API base URL", text: $override, prompt: Text(AppEnvironment.productionBaseURL.absoluteString))
                    .onSubmit(apply)
                HStack {
                    Text("Using \(model.environment.baseURL.absoluteString)").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Use Production") { override = ""; apply() }
                        .disabled(model.environment.isUsingProductionURL)
                    Button("Apply", action: apply)
                }
                if rejected {
                    Text("Only Foundry's own hosts or localhost are allowed, because your sign-in is sent with every request.")
                        .font(.callout).foregroundStyle(.orange)
                }
            } header: {
                Text("Server")
            } footer: {
                Text("For testing against a local or preview server. Each server keeps its own sign-in, so switching back to production finds you still signed in.")
                    .foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Version", value: "\(model.environment.appVersion) (\(model.environment.buildNumber))")
                Button("Open Foundry on the Web") { model.openFoundryWeb() }
            }
        }
        .formStyle(.grouped)
    }

    private func apply() {
        let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let url = URL(string: trimmed), !AppEnvironment.isAllowedOverride(url) {
            rejected = true
            return
        }
        rejected = false
        model.environment.setBaseURLOverride(trimmed)
        model.serverChanged()
    }
}
