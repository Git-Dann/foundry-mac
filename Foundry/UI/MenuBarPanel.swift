import SwiftUI

/// The menu-bar window. Renders straight from the store's in-memory (cached) list, so it opens
/// at once; a refresh runs behind it only when the list is over a minute old.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            if model.auth.isSignedIn {
                header
                VStack(spacing: 8) {
                    QuickAddField()
                    SuggestionsCard()
                    UndoBar()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                Divider()
                list
                Divider()
                footer
            } else {
                SignInPrompt(compact: true).padding(20)
            }
        }
        .frame(width: 360)
        .animation(.easeOut(duration: 0.15), value: model.lastCompleted?.id)
        .onAppear {
            model.openWindowAction = { openWindow(id: "main") }
            model.refreshIfStale()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("To-dos").font(.headline)
            Spacer()
            if model.store.isRefreshing || model.store.isCheckingSources {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await model.store.checkSources() }
            } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Check sources now")
                .disabled(model.store.isCheckingSources)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var list: some View {
        let now = Date()
        let sections = CommitmentGrouping.sections(model.store.items, now: now, include: [.overdue, .today, .next7, .later, .noDate])
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if sections.isEmpty {
                    Text(model.store.loadedAt == nil ? "Loading your to-dos…" : "Nothing to do. A good day.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                }
                ForEach(sections, id: \.group) { section in
                    SectionHeader(title: section.group.title, count: section.items.count, tint: section.group == .overdue ? .red : nil)
                    ForEach(section.items) { c in
                        CommitmentRow(commitment: c, compact: true)
                            .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .frame(minHeight: 120, maxHeight: 460)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.store.isOffline || !model.network.isOnline {
                Label("Offline", systemImage: "wifi.slash")
                    .foregroundStyle(.secondary)
                    .help(model.store.pendingCount > 0 ? "\(model.store.pendingCount) change(s) will be sent when you're back online." : "Showing what was saved.")
            } else if let error = model.store.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .help(error)
            } else if let at = model.store.loadedAt {
                Text("Updated \(at.formatted(.relative(presentation: .named)))").foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Open Window") { model.showInWindow(id: nil) }
                .buttonStyle(.borderless)
            Button { openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings")
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

struct SectionHeader: View {
    let title: String
    var count: Int?
    var tint: Color?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(tint ?? .secondary)
            if let count {
                Text("\(count)").foregroundStyle(.tertiary).monospacedDigit()
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The menu bar's own label: a tick, plus how many are due now when there are any.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let count = model.auth.isSignedIn ? CommitmentGrouping.dueNowCount(model.store.items, now: Date()) : 0
        Group {
            if count > 0 {
                Label("\(count)", systemImage: "checklist")
                    .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: "checklist")
            }
        }
        // The label exists from launch, so this is where the app learns how to open its window
        // (for the hotkey, notifications, widget taps and the Shortcuts intent).
        .onAppear { model.openWindowAction = { openWindow(id: "main") } }
    }
}

struct SignInPrompt: View {
    @Environment(AppModel.self) private var model
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 10 : 14) {
            Image(systemName: "checklist")
                .font(.system(size: compact ? 28 : 44, weight: .light))
                .foregroundStyle(.tint)
            Text("Your to-dos and your Foundry work, in one list")
                .font(compact ? .headline : .title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Your own to-dos beside the board tasks assigned to you, with your calendar. Foundry may suggest the odd thing from your meetings; nothing is added or sent without you.")
                .font(compact ? .callout : .body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button {
                model.auth.signIn(baseURL: model.environment.baseURL)
            } label: {
                Text(model.auth.isAuthenticating ? "Waiting for your browser…" : "Sign in with Foundry")
                    .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(compact ? .regular : .large)
            if model.auth.isAuthenticating {
                Button("Cancel") { model.auth.cancelSignIn() }.buttonStyle(.borderless)
            }
            if let error = model.auth.lastError {
                Text(error).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
    }
}
