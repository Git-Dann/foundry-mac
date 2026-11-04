import SwiftUI

/// The menu-bar window. Renders straight from the store's in-memory (cached) list, so it opens
/// at once; a refresh runs behind it only when the list is over a minute old.
///
/// Liquid Glass (macOS 26+): the panel is already glass, so glass goes on the CONTROLS only
/// (quick add, the round header buttons, Add/Not mine). The list itself is plain content on
/// the panel; glass layered on glass reads as muddy, which is what the old grey slabs did.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            if model.auth.isSignedIn {
                header
                VStack(spacing: 10) {
                    QuickAddField()
                    UndoBar()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                list
                footer
            } else {
                SignInPrompt(compact: true).padding(24)
            }
        }
        .frame(width: 400)
        .buttonBorderShape(.capsule)
        .animation(.smooth(duration: 0.25), value: model.lastCompleted?.id)
        .animation(.smooth(duration: 0.25), value: model.store.items.map(\.state))
        .onAppear {
            model.openWindowAction = { openWindow(id: "main") }
            model.refreshIfStale()
        }
    }

    private var header: some View {
        let now = Date()
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(now.formatted(.dateTime.weekday(.wide)))
                    .font(.title2.weight(.bold))
                Text(PanelSummary.line(model.store.items, now: now))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    GlassIconButton(symbol: "arrow.clockwise", help: "Refresh", spinning: model.store.isRefreshing || model.store.isCheckingSources) {
                        Task { await model.store.checkSources() }
                    }
                    GlassIconButton(symbol: "macwindow", help: "Open the Foundry window") {
                        model.showInWindow(id: nil)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    /// A native List with Sections: system spacing, section headers, keyboard, swipe actions.
    private var list: some View {
        let now = Date()
        let sections = CommitmentGrouping.sections(model.store.items, now: now, include: [.overdue, .today, .next7, .later, .noDate])
        let review = CommitmentGrouping.suggestions(model.store.items)
        return List {
            if !review.isEmpty {
                Section {
                    ForEach(review.prefix(3)) { SuggestionRow(commitment: $0, compact: true) }
                } header: {
                    SuggestionsHeader(count: review.count)
                }
            }
            ForEach(sections, id: \.group) { section in
                Section {
                    ForEach(section.items.prefix(section.group == .later || section.group == .noDate ? 4 : 50)) { c in
                        CommitmentRow(commitment: c, compact: true)
                    }
                } header: {
                    Text(section.group.title)
                        .foregroundStyle(section.group == .overdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
            }
        }
        .listStyle(.inset)
        .contentMargins(.vertical, 4, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .overlay {
            if sections.isEmpty && review.isEmpty {
                ContentUnavailableView(
                    model.store.loadedAt == nil ? "Loading" : "Nothing to do",
                    systemImage: model.store.loadedAt == nil ? "hourglass" : "checkmark.circle",
                    description: Text(model.store.loadedAt == nil ? "Fetching your to-dos." : "A good day.")
                )
            }
        }
        .frame(height: 440)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.store.isOffline || !model.network.isOnline {
                Label("Offline · showing what was saved", systemImage: "wifi.slash")
            } else if let problem = model.store.boardProblem {
                Label(problem, systemImage: "exclamationmark.circle").lineLimit(1).help(problem)
            } else if let at = model.store.loadedAt {
                Text("Updated \(at.formatted(.relative(presentation: .named)))")
            }
            Spacer()
            Button { openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain)
                .help("Settings")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }
}

enum PanelSummary {
    /// "1 due today · 13 on your boards" / "Overdue: 2 · 1 due today" / "All clear".
    static func line(_ items: [Commitment], now: Date) -> String {
        let overdue = CommitmentGrouping.sections(items, now: now, include: [.overdue]).first?.items.count ?? 0
        let today = CommitmentGrouping.sections(items, now: now, include: [.today]).first?.items.count ?? 0
        let board = items.filter { $0.isBoardTask && $0.state == .open }.count
        var parts: [String] = []
        if overdue > 0 { parts.append("\(overdue) overdue") }
        if today > 0 { parts.append("\(today) due today") }
        if board > 0 { parts.append("\(board) on your boards") }
        return parts.isEmpty ? "All clear" : parts.joined(separator: " · ")
    }
}

/// A round glass button for the panel header.
struct GlassIconButton: View {
    let symbol: String
    let help: String
    var spinning = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .symbolEffect(.rotate, isActive: spinning)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help(help)
        .accessibilityLabel(help)
    }
}



/// "Today 17:00 · CAMPFIRE" — when, and whose.
struct RowMeta: View {
    let commitment: Commitment
    var subtitle: String?

    private var isOverdue: Bool { (commitment.dueAt.map { $0 < Date() } ?? false) && commitment.state == .open }

    var body: some View {
        let parts: [String] = [
            commitment.isBoardTask ? commitment.counterpart : nil,
            subtitle ?? (commitment.isBoardTask ? nil : commitment.counterpart),
        ].compactMap { $0 }.filter { !$0.isEmpty }
        HStack(spacing: 4) {
            if let due = commitment.dueAt, commitment.state == .open {
                Text(DueText.string(due)).foregroundStyle(isOverdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                if !parts.isEmpty { Text("·").foregroundStyle(.tertiary) }
            }
            if !parts.isEmpty {
                Text(parts.joined(separator: " · ")).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .font(.caption)
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
            .buttonStyle(.glassProminent)
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
