import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class RideLibrary {
    private(set) var rides: [RideRecord] = []
    private(set) var errorMessage: String?

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
}
