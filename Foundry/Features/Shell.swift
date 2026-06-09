import SwiftUI

/// Shared toolbar chrome applied to every feature pane: New Proposal, Refresh, a sync-status
/// indicator, and the account menu. The toolbar surface itself is system Liquid Glass.
struct FoundryToolbar: ToolbarContent {
    let model: AppModel

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
            Image(systemName: model.network.isOnline ? "checkmark.circle.fill" : "wifi.slash")
                .foregroundStyle(model.network.isOnline ? Color.green : Color.orange)
                .imageScale(.small)
            if let last = model.lastRefresh {
                Text(last, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .help(model.network.isOnline ? "Online" : "Offline")
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
