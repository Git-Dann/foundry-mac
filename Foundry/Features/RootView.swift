import SwiftUI

/// Every Foundry module, in the same order + naming as the web sidebar. Native modules render a
/// native view; Study (heavy multi-agent) opens the hosted screen in the controlled WebKit pane.
/// Settings is pinned to the sidebar footer (with the account), not in the scrolling list.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard   // "Foundry HQ"
    case pulse
    case codeclear   // "Code"
    case proposals   // "Docs"
    case clients     // "Portal"
    case care
    case study
    case backstage
    case settings

    var id: String { rawValue }

    /// The modules shown in the main scrolling list (Settings lives in the footer).
    static let primary: [SidebarItem] = [.dashboard, .pulse, .codeclear, .proposals, .clients, .care, .study, .backstage]

    var title: String {
        switch self {
        case .dashboard: return "Foundry HQ"
        case .pulse: return "Pulse"
        case .codeclear: return "Code"
        case .proposals: return "Docs"
        case .clients: return "Portal"
        case .care: return "Care"
        case .study: return "Study"
        case .backstage: return "Backstage"
        case .settings: return "Settings"
        }
    }

    var subtitle: String? {
        switch self {
        case .dashboard: return nil
        case .pulse: return "Health and delivery tracking"
        case .codeclear: return "Dev review and validation"
        case .proposals: return "Proposals, SLAs, SOWs and other documents"
        case .clients: return "Client management"
        case .care: return "Support and aftercare"
        case .study: return "AI-powered user research"
        case .backstage: return "Internal team ops — leave, expenses, availability"
        case .settings: return nil
        }
    }

    /// SF Symbols chosen to mirror the web sidebar's iconography.
    var systemImage: String {
        switch self {
        case .dashboard: return "building.2"
        case .pulse: return "dot.radiowaves.left.and.right"
        case .codeclear: return "chevron.left.forwardslash.chevron.right"
        case .proposals: return "doc.text"
        case .clients: return "person.3"
        case .care: return "lifepreserver"
        case .study: return "graduationcap"
        case .backstage: return "wrench.and.screwdriver"
        case .settings: return "gearshape"
        }
    }

}

/// The app's native window content: a `NavigationSplitView` with a system sidebar, gated by
/// the sign-in state. Liquid Glass comes for free from the standard sidebar + toolbar.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.auth.isSignedIn {
                NavigationSplitView {
                    SidebarView(selection: $model.selection)
                } detail: {
                    DetailColumn(selection: model.selection)
                }
            } else {
                SignInView()
            }
        }
        .frame(minWidth: 900, minHeight: 580)
    }
}

private struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            ForEach(SidebarItem.primary) { item in
                SidebarRow(item: item).tag(item)
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 252, max: 340)
        .navigationTitle("Foundry")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Button { selection = .settings } label: {
                    SidebarRow(item: .settings)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .background(
                            selection == .settings ? Color.accentColor.opacity(0.15) : .clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.top, 6)

                SidebarAccountFooter()
                    .padding(10)
            }
            .background(.bar)
        }
    }
}

/// A sidebar row: icon + title with an optional grey subtitle (mirrors the web).
private struct SidebarRow: View {
    let item: SidebarItem

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: item.systemImage)
        }
        .padding(.vertical, 2)
    }
}

/// Account identity pinned at the very bottom (matches the web's footer card).
private struct SidebarAccountFooter: View {
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
            SettingsLink { Text("App Settings…") }
            Divider()
            Button("Sign Out", role: .destructive) { model.auth.signOut() }
        } label: {
            HStack(spacing: 10) {
                InitialsAvatar(name: model.auth.currentUser?.displayName ?? "?", url: nil, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.auth.currentUser?.displayName ?? "Account").font(.callout.weight(.medium)).lineLimit(1)
                    if let email = model.auth.currentUser?.email {
                        Text(email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
}

/// Hosts the selected feature inside a `NavigationStack` (for list → detail push) and applies
/// the shared toolbar chrome. Native modules render their SwiftUI view; Study opens in the
/// controlled WebKit pane.
private struct DetailColumn: View {
    @Environment(AppModel.self) private var model
    let selection: SidebarItem?

    var body: some View {
        NavigationStack {
            content
                .toolbar { FoundryToolbar(model: model) }
        }
        .id(selection)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .dashboard: DashboardView()
        case .pulse: PulseView()
        case .proposals: ProposalsView()
        case .clients: ClientsView()
        case .care: CareView()
        case .study: StudyView()
        case .codeclear: CodeClearView()
        case .backstage: BackstageView()
        case .settings: SettingsModuleView()
        case .none:
            ContentUnavailableView("Select a section", systemImage: "sidebar.left")
        }
    }
}
