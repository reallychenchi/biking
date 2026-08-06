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
        await refreshRideStatisticsIfNeeded()
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

    private func refreshRideStatisticsIfNeeded() async {
        do {
            let currentVersion = try AppVersionState.currentVersion()
            guard AppVersionState.lastRefreshedStatisticsVersion != currentVersion else { return }

            let updatedCount = try await repository.refreshCompletedRideDerivedMetrics()
            AppVersionState.lastRefreshedStatisticsVersion = currentVersion
            AppLog.persistence.info("Refreshed ride statistics for app version \(currentVersion, privacy: .public), updated rides: \(updatedCount)")
        } catch {
            AppLog.persistence.error("Failed to refresh ride statistics for app version change: \(error.localizedDescription, privacy: .public)")
        }
    }
}

enum AppVersionState {
    private static let statisticsVersionKey = "cc.chenchi.bike.statisticsRefreshedAppVersion"

    static var lastRefreshedStatisticsVersion: String? {
        get { UserDefaults.standard.string(forKey: statisticsVersionKey) }
        set { UserDefaults.standard.set(newValue, forKey: statisticsVersionKey) }
    }

    static func currentVersion(bundle: Bundle = .main) throws -> String {
        guard let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
              !version.isEmpty else {
            assertionFailure("Missing CFBundleShortVersionString")
            throw AppVersionError.missingShortVersion
        }
        return version
    }
}

enum AppVersionError: LocalizedError {
    case missingShortVersion

    var errorDescription: String? {
        "无法读取当前 App 版本号。"
    }
}
