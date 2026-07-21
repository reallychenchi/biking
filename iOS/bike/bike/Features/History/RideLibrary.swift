import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class RideLibrary {
    private(set) var rides: [RideRecord] = []
    private(set) var errorMessage: String?
    private(set) var undoBannerMessage: String?

    private var pendingDelete: RideRecord?
    private var commitTask: Task<Void, Never>?

    private let repository: any RideRepository

    init(repository: any RideRepository) {
        self.repository = repository
    }

    func reload() async {
        do {
            rides = try await repository.completedRides()
            errorMessage = nil
        } catch {
            errorMessage = "历史记录读取失败：\(error.localizedDescription)"
            AppLog.persistence.error("Failed to load ride history: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stageDelete(ride: RideRecord) {
        commitTask?.cancel()
        if let previous = pendingDelete {
            Task { [repository] in
                do {
                    try await repository.deleteRide(id: previous.id)
                } catch {
                    AppLog.persistence.error("Failed to delete ride: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        rides.removeAll { $0.id == ride.id }
        pendingDelete = ride
        undoBannerMessage = "已删除 \(RideFormatting.date(ride.startDate)) 的骑行"
        commitTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await commitPendingDelete()
        }
    }

    func undoDelete() {
        commitTask?.cancel()
        commitTask = nil
        guard let ride = pendingDelete else { return }
        pendingDelete = nil
        undoBannerMessage = nil
        rides.append(ride)
        rides.sort { $0.startDate > $1.startDate }
    }

    private func commitPendingDelete() async {
        guard let ride = pendingDelete else { return }
        pendingDelete = nil
        undoBannerMessage = nil
        commitTask = nil
        do {
            try await repository.deleteRide(id: ride.id)
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
            AppLog.persistence.error("Failed to delete ride: \(error.localizedDescription, privacy: .public)")
            rides.append(ride)
            rides.sort { $0.startDate > $1.startDate }
        }
    }
}
