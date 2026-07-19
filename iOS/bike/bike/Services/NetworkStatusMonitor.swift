import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkStatusMonitor {
    private(set) var isOffline = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "cc.chenchi.bike.network-status")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            guard let monitorOwner = self else { return }
            Task { @MainActor [monitorOwner] in
                monitorOwner.isOffline = offline
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
