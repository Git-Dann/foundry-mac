import SwiftUI

/// Shown when no valid session exists. Sign-in runs through ASWebAuthenticationSession
/// (Google login on the real Foundry site → per-user JWT). No credentials are handled in-app.
struct SignInView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(Color.foundryBlue)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Foundry")
                    .font(.largeTitle.weight(.bold))
                Text("Sign in with your Gitwork Google account to continue.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                model.signIn()
            } label: {
                if model.auth.isAuthenticating {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Sign in to Foundry")
                        .frame(minWidth: 200)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.auth.isAuthenticating)
            .keyboardShortcut(.defaultAction)

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
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
