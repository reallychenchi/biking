import Foundation
import SwiftData

@Model
final class RideEntity {
    @Attribute(.unique) var id: UUID
    var statusRawValue: String
    var startDate: Date
    var endDate: Date?
    var elapsedSeconds: Double
    var distanceMeters: Double
    var maximumSpeedMetersPerSecond: Double
    var averageSpeedMetersPerSecond: Double
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var points: [TrackPointEntity]

    init(id: UUID, startDate: Date, createdAt: Date) {
        self.id = id
        statusRawValue = RideStatus.recording.rawValue
        self.startDate = startDate
        endDate = nil
        elapsedSeconds = 0
        distanceMeters = 0
        maximumSpeedMetersPerSecond = 0
        averageSpeedMetersPerSecond = 0
        self.createdAt = createdAt
        updatedAt = createdAt
        points = []
    }
}

@Model
final class TrackPointEntity {
    @Attribute(.unique) var id: UUID
    var sequence: Int
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var horizontalAccuracy: Double
    var systemSpeedMetersPerSecond: Double?
    var segmentIndex: Int

    init(point: TrackPoint) {
        id = point.id
        sequence = point.sequence
        latitude = point.latitude
        longitude = point.longitude
        timestamp = point.timestamp
        horizontalAccuracy = point.horizontalAccuracy
        systemSpeedMetersPerSecond = point.systemSpeedMetersPerSecond
        segmentIndex = point.segmentIndex
    }

    var domainModel: TrackPoint {
        TrackPoint(
            id: id,
            sequence: sequence,
            latitude: latitude,
            longitude: longitude,
            timestamp: timestamp,
            horizontalAccuracy: horizontalAccuracy,
            systemSpeedMetersPerSecond: systemSpeedMetersPerSecond,
            segmentIndex: segmentIndex
        )
    }
}
