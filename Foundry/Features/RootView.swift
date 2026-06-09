import SwiftUI

/// Sidebar groupings. Order is top-to-bottom in the sidebar.
enum SidebarSection: String, CaseIterable, Identifiable {
    case workspace = "Workspace"
    case delivery = "Delivery"
    case operations = "Operations"
    case admin = "Admin"

    var id: String { rawValue }
}

/// Every Foundry module, reachable from the Mac sidebar. Native modules render a native view;
/// the rest open the hosted screen in the controlled WebKit pane (`webDestination`) until they're
/// rebuilt natively in a later phase. Calendar gets its own window (added in a later version),
/// so it is not a sidebar item.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case pulse
    case proposals   // "Docs"
    case clients     // "Portal"
    case care
    case study
    case codeclear   // "Code"
    case backstage
    case rateCard
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .pulse: return "Pulse"
        case .proposals: return "Docs"
        case .clients: return "Portal"
        case .care: return "Care"
        case .study: return "Study"
        case .codeclear: return "Code"
        case .backstage: return "Backstage"
        case .rateCard: return "Rate Card"
        case .settings: return "Settings"
        }
    }

    /// SF Symbols — native iconography, no custom assets needed.
    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .pulse: return "waveform.path.ecg"
        case .proposals: return "doc.text"
        case .clients: return "building.2"
        case .care: return "bubble.left.and.bubble.right"
        case .study: return "person.3.sequence"
        case .codeclear: return "chevron.left.forwardslash.chevron.right"
        case .backstage: return "briefcase"
        case .rateCard: return "sterlingsign.circle"
        case .settings: return "gearshape"
        }
    }

    var section: SidebarSection {
        switch self {
        case .dashboard: return .workspace
        case .pulse, .proposals, .clients, .care, .study, .codeclear: return .delivery
        case .backstage, .rateCard: return .operations
        case .settings: return .admin
        }
    }

    /// Non-nil for modules not yet rebuilt natively — they open in the in-app WebKit pane.
    /// `nil` means a native SwiftUI screen handles this module (see `DetailColumn`).
    var webDestination: WebDestination? {
        switch self {
        case .pulse: return .pulse
        case .care: return .care
        case .study: return .study
        case .backstage: return .backstage
        case .settings: return .workspaceSettings
        case .dashboard, .proposals, .clients, .codeclear, .rateCard: return nil
        }
    }

    static func items(in section: SidebarSection) -> [SidebarItem] {
        allCases.filter { $0.section == section }
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
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            ForEach(SidebarSection.allCases) { section in
                Section(section.rawValue) {
                    ForEach(SidebarItem.items(in: section)) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(item)
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 320)
        .navigationTitle("Foundry")
    }
}

/// Hosts the selected feature inside a `NavigationStack` (for list → detail push) and applies
/// the shared toolbar chrome. Native modules render their SwiftUI view; everything else opens
/// the hosted screen in the controlled WebKit pane.
private struct DetailColumn: View {
    @Environment(AppModel.self) private var model
    let selection: SidebarItem?

    var body: some View {
        NavigationStack {
            content
                .toolbar { FoundryToolbar(model: model) }
        }
        // Re-create the pane when the module changes so each gets a clean NavigationStack
        // (and the WebKit pane reloads its route rather than animating a push).
        .id(selection)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .dashboard: DashboardView()
        case .proposals: ProposalsView()
        case .clients: ClientsView()
        case .codeclear: CodeClearView()
        case .rateCard: RateCardView()
        case .none:
            ContentUnavailableView("Select a section", systemImage: "sidebar.left")
        default:
            if let destination = selection?.webDestination {
                FoundryWebScreen(destination: destination)
            } else {
                ContentUnavailableView("Select a section", systemImage: "sidebar.left")
            }
        }
    }
}
