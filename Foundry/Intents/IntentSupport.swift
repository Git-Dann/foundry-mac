import Foundation

/// Builds an API client for use inside App Intents. Reuses the same Keychain-backed token and
/// base URL as the app (intents run in the app's process), so no extra auth wiring is needed.
@MainActor
func foundryIntentClient() -> FoundryAPIClient {
    FoundryAPIClient(environment: AppEnvironment(), auth: AuthStore())
}
