import Foundation
import Observation
import Sparkle

/// Wraps Sparkle's `SPUStandardUpdaterController` for SwiftUI. Exposes whether a check can run
/// (to enable/disable the menu item) and the automatic-check preference (Settings → Updates).
///
/// Sparkle is the ONLY update mechanism and is Mac-only. The feed URL + public EdDSA key live
/// in Info.plist (`SUFeedURL` / `SUPublicEDKey`); update archives are EdDSA-signed.
@MainActor
@Observable
final class UpdateController {
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    private(set) var canCheckForUpdates = false

    var automaticallyChecksForUpdates: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    init() {
        // Starts the updater immediately; it reads SUFeedURL + SUPublicEDKey from Info.plist.
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        canCheckForUpdates = controller.updater.canCheckForUpdates
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = value }
        }
    }

    /// User-initiated check (shows Sparkle's UI, including "you're up to date").
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var feedURLString: String {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "—"
    }

    var lastUpdateCheckDescription: String {
        guard let date = controller.updater.lastUpdateCheckDate else { return "Never" }
        return Formatters.medium(date)
    }
}
