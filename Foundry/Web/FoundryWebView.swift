import SwiftUI
import WebKit
import AppKit

/// `WKWebView` wrapped for SwiftUI as a controlled bridge to hosted Foundry screens.
/// Enforces the origin allow-list, routes external links to the system browser, surfaces
/// load progress + errors, and injects no secrets and no broad JavaScript bridge.
struct FoundryWebView: NSViewRepresentable {
    let url: URL
    let baseURL: URL
    @Binding var isLoading: Bool
    @Binding var estimatedProgress: Double
    @Binding var errorMessage: String?
    let openExternal: (URL) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Persist cookies/session in the shared default store so a single in-pane Foundry login
        // sticks across every embedded module and across app launches (no repeated sign-in).
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.startObserving(webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: FoundryWebView
        private var progressObservation: NSKeyValueObservation?

        init(_ parent: FoundryWebView) { self.parent = parent }

        func startObserving(_ webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { webView, _ in
                let value = webView.estimatedProgress
                Task { @MainActor in self.parent.estimatedProgress = value }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                parent.isLoading = true
                parent.errorMessage = nil
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in parent.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        private func report(_ error: Error) {
            // Ignore "frame load interrupted" (-999) caused by our own redirect cancellations.
            if (error as NSError).code == NSURLErrorCancelled { return }
            Task { @MainActor in
                parent.isLoading = false
                parent.errorMessage = error.localizedDescription
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if WebNavigationPolicy.isAllowed(url, base: parent.baseURL) {
                decisionHandler(.allow)
            } else {
                // External or disallowed scheme → open in the user's default browser.
                if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                    parent.openExternal(url)
                }
                decisionHandler(.cancel)
            }
        }
    }
}

/// Native chrome around the WebKit bridge: a linear progress bar, an error overlay with retry,
/// and an "Open in Browser" toolbar action.
struct FoundryWebScreen: View {
    @Environment(AppModel.self) private var model
    let destination: WebDestination

    @State private var isLoading = true
    @State private var progress = 0.0
    @State private var errorMessage: String?
    @State private var reloadToken = 0

    private var url: URL { destination.resolvedURL(base: model.environment.baseURL) }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && progress < 1 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
            ZStack {
                FoundryWebView(
                    url: url,
                    baseURL: model.environment.baseURL,
                    isLoading: $isLoading,
                    estimatedProgress: $progress,
                    errorMessage: $errorMessage,
                    openExternal: { NSWorkspace.shared.open($0) }
                )
                .id(reloadToken)

                if let errorMessage {
                    ErrorStateView(message: errorMessage) {
                        self.errorMessage = nil
                        progress = 0
                        reloadToken &+= 1
                    }
                    .background(.background)
                }
            }
        }
        .navigationTitle(destination.title)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button { reloadToken &+= 1 } label: { Label("Reload", systemImage: "arrow.clockwise") }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { NSWorkspace.shared.open(url) } label: { Label("Open in Browser", systemImage: "safari") }
            }
        }
    }
}
