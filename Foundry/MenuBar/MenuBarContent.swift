import SwiftUI
import AppKit

/// The menu-bar dropdown (`MenuBarExtra`, `.window` style).
///
/// Runs in the main app process — no App Group, no extension — so the figures are LIVE.
/// Surfaces today + month-to-date AI spend (Super-Admin only; via `GET /api/admin/ai-cost`) and
/// quick actions. Any spend fetch failure (including the expected 403 for non-super-admins, or the
/// endpoint predating the mobile-JWT change) simply hides the spend block — never an error.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    var checkForUpdates: (() -> Void)?

    @State private var cost: AiCostSummary?
    @State private var loadingCost = false

    private var isSuperAdmin: Bool { model.auth.currentUser?.role == "SUPER_ADMIN" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.auth.isSignedIn {
                if isSuperAdmin { spendSection; Divider() }
                actions
            } else {
                Text("You're signed out.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Sign in to Foundry") { model.signIn() }
            }
        }
        .padding(14)
        .frame(width: 290)
        .task(id: model.auth.token) { await refreshCost() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "hammer.fill").foregroundStyle(Color.foundryBlue)
            Text("Foundry").font(.headline)
            Spacer()
            if let user = model.auth.currentUser {
                Text(user.roleLabel).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var spendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI SPEND").font(.caption.monospaced()).foregroundStyle(.secondary)
            if let cost, cost.configured {
                HStack(alignment: .top, spacing: 20) {
                    spendStat("Today", cost.totalToday, cost.commonCurrency ?? "USD")
                    spendStat("This month", cost.totalMonthToDate, cost.commonCurrency ?? "USD")
                    Spacer()
                }
                ForEach(cost.providers.filter { $0.status == .ok }) { provider in
                    HStack {
                        Text(provider.providerLabel).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(Formatters.currency(provider.monthToDate, code: provider.currency))
                            .font(.caption.monospacedDigit())
                    }
                }
            } else if loadingCost {
                ProgressView().controlSize(.small)
            } else {
                Text(cost == nil ? "Spend unavailable" : "No provider key configured")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func spendStat(_ label: String, _ amount: Double, _ code: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Formatters.currency(amount, code: code))
                .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 2) {
            menuButton("New Proposal", systemImage: "square.and.pencil") {
                NSApp.activate(ignoringOtherApps: true)
                model.requestNewProposal()
            }
            menuButton("Open Foundry Web", systemImage: "safari") { model.openWeb() }
            menuButton("Open Calendar", systemImage: "calendar") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "calendar")
            }
            if let checkForUpdates {
                menuButton("Check for Updates…", systemImage: "arrow.down.circle") { checkForUpdates() }
            }
            Divider()
            menuButton("Quit Foundry", systemImage: "power") { NSApp.terminate(nil) }
        }
    }

    private func menuButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func refreshCost() async {
        guard model.auth.isSignedIn, isSuperAdmin else { cost = nil; return }
        loadingCost = true
        defer { loadingCost = false }
        cost = try? await model.api.aiCost()
    }
}
