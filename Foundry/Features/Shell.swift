import SwiftUI

/// Shared toolbar chrome applied to every feature pane: New Proposal, Refresh, a sync-status
/// indicator, and the account menu. The toolbar surface itself is system Liquid Glass.
struct FoundryToolbar: ToolbarContent {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.requestNewProposal()
            } label: {
                Label("New Proposal", systemImage: "square.and.pencil")
            }
            .help("New Proposal (⌘N)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.requestRefresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh (⌘R)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                openWindow(id: "calendar")
            } label: {
                Label("Calendar", systemImage: "calendar")
            }
            .help("Open Calendar")
        }
        ToolbarItem(placement: .primaryAction) {
            SyncStatusView()
        }
        ToolbarItem(placement: .primaryAction) {
            AccountMenu()
        }
    }
}

/// Compact online/last-refresh indicator.
private struct SyncStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(model.network.isOnline ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            if let last = model.lastRefresh {
                Text(last, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if !model.network.isOnline {
                Text("Offline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .help(model.network.isOnline ? "Online — time of last refresh" : "Offline")
        .accessibilityLabel(model.network.isOnline ? "Online" : "Offline")
    }
}

/// Account menu — identity, quick links, and sign out.
private struct AccountMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            if let user = model.auth.currentUser {
                Section {
                    Text(user.displayName)
                    Text(user.roleLabel)
                }
            }
            Button("Open Foundry Web") { model.openWeb() }
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Sign Out", role: .destructive) { model.auth.signOut() }
        } label: {
            Label("Account", systemImage: "person.crop.circle")
        }
        .help(model.auth.currentUser?.email ?? "Account")
    }
}
