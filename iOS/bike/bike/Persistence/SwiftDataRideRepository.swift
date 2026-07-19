import Foundation
import SwiftData

@ModelActor
actor SwiftDataRideRepository: RideRepository {
    func createTemporaryRide(id: UUID, startDate: Date, createdAt: Date) throws {
        modelContext.insert(RideEntity(id: id, startDate: startDate, createdAt: createdAt))
        try modelContext.save()
    }

    func appendCheckpoint(rideID: UUID, points: [TrackPoint], progress: RideProgress) throws {
        let ride = try requireRide(id: rideID)
        appendUnique(points, to: ride)
        apply(progress, to: ride)
        try modelContext.save()
    }

    func completeRide(_ completion: RideCompletionSnapshot, pendingPoints: [TrackPoint]) throws {
        let ride = try requireRide(id: completion.rideID)
        appendUnique(pendingPoints, to: ride)
        apply(completion.progress, to: ride)
        ride.statusRawValue = RideStatus.completed.rawValue
        ride.endDate = completion.endDate
        try modelContext.save()
    }

    func completedRides() throws -> [RideRecord] {
        let descriptor = FetchDescriptor<RideEntity>(
            sortBy: [SortDescriptor(\RideEntity.startDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
            .filter { $0.statusRawValue == RideStatus.completed.rawValue }
            .map(domainModel)
    }

    func unfinishedRideIDs() throws -> [UUID] {
        try modelContext.fetch(FetchDescriptor<RideEntity>())
            .filter { $0.statusRawValue == RideStatus.recording.rawValue }
            .map(\.id)
    }

    func discardUnfinishedRides() throws {
        let unfinished = try modelContext.fetch(FetchDescriptor<RideEntity>())
            .filter { $0.statusRawValue == RideStatus.recording.rawValue }
        unfinished.forEach(modelContext.delete)
        try modelContext.save()
    }

    private func requireRide(id: UUID) throws -> RideEntity {
        let descriptor = FetchDescriptor<RideEntity>(predicate: #Predicate { $0.id == id })
        guard let ride = try modelContext.fetch(descriptor).first else {
            throw RideRepositoryError.rideNotFound(id)
        }
        return ride
    }

    private func appendUnique(_ points: [TrackPoint], to ride: RideEntity) {
        let existingIDs = Set(ride.points.map(\.id))
        ride.points.append(contentsOf: points.filter { !existingIDs.contains($0.id) }.map(TrackPointEntity.init))
    }

    private func apply(_ progress: RideProgress, to ride: RideEntity) {
        ride.elapsedSeconds = progress.elapsedSeconds
        ride.distanceMeters = progress.distanceMeters
        ride.maximumSpeedMetersPerSecond = progress.maximumSpeedMetersPerSecond
        ride.averageSpeedMetersPerSecond = progress.averageSpeedMetersPerSecond
        ride.updatedAt = progress.updatedAt
    }

    private func domainModel(_ entity: RideEntity) throws -> RideRecord {
        guard let status = RideStatus(rawValue: entity.statusRawValue) else {
            throw RideRepositoryError.invalidStoredStatus(entity.statusRawValue)
        }
        return RideRecord(
            id: entity.id,
            status: status,
            startDate: entity.startDate,
            endDate: entity.endDate,
            elapsedSeconds: entity.elapsedSeconds,
            distanceMeters: entity.distanceMeters,
            maximumSpeedMetersPerSecond: entity.maximumSpeedMetersPerSecond,
            averageSpeedMetersPerSecond: entity.averageSpeedMetersPerSecond,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            points: entity.points.map(\.domainModel).sorted { $0.sequence < $1.sequence }
        )
    }
}
