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

    func completedRideSummaries() throws -> [RideSummary] {
        let completedStatus = RideStatus.completed.rawValue
        let descriptor = FetchDescriptor<RideEntity>(
            predicate: #Predicate { ride in
                ride.statusRawValue == completedStatus
            },
            sortBy: [SortDescriptor(\RideEntity.startDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(summaryModel)
    }

    func completedRide(id: UUID) throws -> RideRecord {
        let completedStatus = RideStatus.completed.rawValue
        var descriptor = FetchDescriptor<RideEntity>(
            predicate: #Predicate { ride in
                ride.id == id && ride.statusRawValue == completedStatus
            }
        )
        descriptor.fetchLimit = 1
        descriptor.relationshipKeyPathsForPrefetching = [\RideEntity.points]

        guard let entity = try modelContext.fetch(descriptor).first else {
            throw RideRepositoryError.rideNotFound(id)
        }
        return try domainModel(entity)
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

    func deleteRide(id: UUID) throws {
        let ride = try requireRide(id: id)
        modelContext.delete(ride)
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
        ride.totalElapsedSeconds = progress.totalElapsedSeconds
        ride.movingElapsedSeconds = progress.movingElapsedSeconds
        ride.distanceMeters = progress.distanceMeters
        ride.maximumSpeedMetersPerSecond = progress.maximumSpeedMetersPerSecond
        ride.overallSpeedMetersPerSecond = progress.overallSpeedMetersPerSecond
        ride.averageSpeedMetersPerSecond = progress.averageSpeedMetersPerSecond
        ride.cumulativeAscentMeters = progress.cumulativeAscentMeters
        ride.cumulativeDescentMeters = progress.cumulativeDescentMeters
        ride.minimumAltitudeMeters = progress.minimumAltitudeMeters
        ride.maximumAltitudeMeters = progress.maximumAltitudeMeters
        ride.updatedAt = progress.updatedAt
    }

    private func summaryModel(_ entity: RideEntity) -> RideSummary {
        RideSummary(
            id: entity.id,
            startDate: entity.startDate,
            distanceMeters: entity.distanceMeters,
            averageSpeedMetersPerSecond: entity.averageSpeedMetersPerSecond,
            updatedAt: entity.updatedAt
        )
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
            totalElapsedSeconds: entity.totalElapsedSeconds,
            movingElapsedSeconds: entity.movingElapsedSeconds,
            distanceMeters: entity.distanceMeters,
            maximumSpeedMetersPerSecond: entity.maximumSpeedMetersPerSecond,
            overallSpeedMetersPerSecond: entity.overallSpeedMetersPerSecond,
            averageSpeedMetersPerSecond: entity.averageSpeedMetersPerSecond,
            cumulativeAscentMeters: entity.cumulativeAscentMeters,
            cumulativeDescentMeters: entity.cumulativeDescentMeters,
            minimumAltitudeMeters: entity.minimumAltitudeMeters,
            maximumAltitudeMeters: entity.maximumAltitudeMeters,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            points: entity.points.map(\.domainModel).sorted { $0.sequence < $1.sequence }
        )
    }
}
