import SwiftUI
import AppKit

/// Shown when no valid session exists. Sign-in opens the real Foundry web login in the user's
/// default browser; the `foundry://` callback completes it. No credentials are handled in-app.
struct SignInView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            // Branded canvas — a restrained gradient over the system window background so it
            // adapts to light/dark while reading as a designed surface, not a blank window.
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.07),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 78, height: 78)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("FOUNDRY FOR MAC")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.tertiary)
                    Text("Foundry")
                        .font(.system(size: 40, weight: .semibold, design: .serif))
                        .foregroundStyle(.primary)
                    Text("Sign in with your Gitwork Google account to continue.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }

                if model.auth.isAuthenticating {
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for sign-in in your browser…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Button("Cancel") { model.auth.cancelSignIn() }
                            .buttonStyle(.link)
                    }
                } else {
                    VStack(spacing: 10) {
                        Button {
                            model.signIn()
                        } label: {
                            Text("Sign in to Foundry").frame(minWidth: 220)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)

                        Label("Opens in your default browser", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                if let error = model.auth.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }
                if !model.network.isOnline {
                    Label("You appear to be offline.", systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(44)
            .frame(maxWidth: 460)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 26, y: 8)
            )
            .padding(40)
        }
    }
}
