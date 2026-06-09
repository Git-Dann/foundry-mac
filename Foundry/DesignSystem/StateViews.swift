import SwiftUI

/// Generic async loading state used by feature view models.
enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? { if case .loaded(let v) = self { return v }; return nil }
    var isLoading: Bool { if case .loading = self { return true }; return false }
}

/// Native, centered progress indicator.
struct LoadingView: View {
    var label: String = "Loading…"
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Native error state with a retry affordance (uses the system `ContentUnavailableView`).
struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Native "you need to be online" state.
struct OfflineStateView: View {
    var body: some View {
        ContentUnavailableView(
            "You're offline",
            systemImage: "wifi.slash",
            description: Text("Foundry needs an internet connection to load your workspace.")
        )
    }
}
