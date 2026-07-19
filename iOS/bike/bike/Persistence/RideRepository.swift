import Foundation

protocol RideRepository: Sendable {
    func createTemporaryRide(id: UUID, startDate: Date, createdAt: Date) async throws
    func appendCheckpoint(rideID: UUID, points: [TrackPoint], progress: RideProgress) async throws
    func completeRide(_ completion: RideCompletionSnapshot, pendingPoints: [TrackPoint]) async throws
    func completedRides() async throws -> [RideRecord]
    func unfinishedRideIDs() async throws -> [UUID]
    func discardUnfinishedRides() async throws
}

enum RideRepositoryError: LocalizedError {
    case rideNotFound(UUID)
    case invalidStoredStatus(String)

    var errorDescription: String? {
        switch self {
        case .rideNotFound:
            return "找不到需要保存的骑行记录。"
        case .invalidStoredStatus:
            return "本地骑行记录状态无法识别。"
        }
    }
}
