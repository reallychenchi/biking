import Foundation
import Observation
import OSLog

enum AppTab: Hashable {
    case ride
    case history
    case settings
}

@MainActor
@Observable
final class AppModel {
    var selectedTab: AppTab = .ride
    var showInterruptedRideAlert = false
    private(set) var interruptedRideError: String?

    let rideController: RideSessionController
    let rideLibrary: RideLibrary
    let networkMonitor = NetworkStatusMonitor()

    private let repository: any RideRepository
    private var didStart = false

    init(repository: any RideRepository) {
        self.repository = repository
        let library = RideLibrary(repository: repository)
        let controller = RideSessionController(
            repository: repository,
            trackingService: RideTrackingService()
        )
        controller.onRideSaved = { await library.reload() }
        rideLibrary = library
        rideController = controller
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        await rideLibrary.reload()
        do {
            showInterruptedRideAlert = try await !repository.unfinishedRideIDs().isEmpty
        } catch {
            interruptedRideError = "无法检查上次骑行：\(error.localizedDescription)"
            AppLog.persistence.error("Failed to inspect unfinished rides: \(error.localizedDescription, privacy: .public)")
        }
    }

    func discardInterruptedRide() async {
        do {
            try await repository.discardUnfinishedRides()
            showInterruptedRideAlert = false
            interruptedRideError = nil
            AppLog.persistence.info("Discarded unfinished ride data")
        } catch {
            interruptedRideError = "临时记录删除失败：\(error.localizedDescription)"
            showInterruptedRideAlert = true
            AppLog.persistence.error("Failed to discard unfinished rides: \(error.localizedDescription, privacy: .public)")
        }
    }
}
