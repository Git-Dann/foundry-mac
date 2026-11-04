import Foundation
import Network
import Observation

/// Lightweight reachability for native offline states. Backed by `NWPathMonitor`.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    @ObservationIgnored var onChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "co.gitwork.foundry.network-monitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
                self.onChange?(online)
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
