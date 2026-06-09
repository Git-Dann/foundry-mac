import SwiftUI

/// Top-level sidebar destinations. Order matches the brief.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case proposals
    case clients
    case codeclear
    case rateCard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .proposals: return "Proposals"
        case .clients: return "Clients"
        case .codeclear: return "CodeClear"
        case .rateCard: return "Rate Card"
        }
    }

    /// SF Symbols — native iconography, no custom assets needed.
    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .proposals: return "doc.text"
        case .clients: return "building.2"
        case .codeclear: return "chevron.left.forwardslash.chevron.right"
        case .rateCard: return "person.2.badge.gearshape"
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
    @Binding var selection: SidebarItem?

    var body: some View {
        List(SidebarItem.allCases, selection: $selection) { item in
            Label(item.title, systemImage: item.systemImage)
                .tag(item)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 320)
        .navigationTitle("Foundry")
    }
}

/// Hosts the selected feature inside a `NavigationStack` (for list → detail push) and applies
/// the shared toolbar chrome.
private struct DetailColumn: View {
    @Environment(AppModel.self) private var model
    let selection: SidebarItem?

    var body: some View {
        NavigationStack {
            content
                .toolbar { FoundryToolbar(model: model) }
        }
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
        }
    }
}
