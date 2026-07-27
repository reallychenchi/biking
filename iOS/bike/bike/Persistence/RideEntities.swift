import Foundation
import SwiftData

@Model
final class RideEntity {
    @Attribute(.unique) var id: UUID
    var statusRawValue: String
    var startDate: Date
    var endDate: Date?
    var totalElapsedSeconds: Double
    var movingElapsedSeconds: Double
    var distanceMeters: Double
    var maximumSpeedMetersPerSecond: Double
    var overallSpeedMetersPerSecond: Double
    var averageSpeedMetersPerSecond: Double
    var cumulativeAscentMeters: Double?
    var cumulativeDescentMeters: Double?
    var minimumAltitudeMeters: Double?
    var maximumAltitudeMeters: Double?
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var points: [TrackPointEntity]

    init(id: UUID, startDate: Date, createdAt: Date) {
        self.id = id
        statusRawValue = RideStatus.recording.rawValue
        self.startDate = startDate
        endDate = nil
        totalElapsedSeconds = 0
        movingElapsedSeconds = 0
        distanceMeters = 0
        maximumSpeedMetersPerSecond = 0
        overallSpeedMetersPerSecond = 0
        averageSpeedMetersPerSecond = 0
        cumulativeAscentMeters = nil
        cumulativeDescentMeters = nil
        minimumAltitudeMeters = nil
        maximumAltitudeMeters = nil
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
    var altitudeMeters: Double?
    var verticalAccuracyMeters: Double?
    var segmentIndex: Int

    init(point: TrackPoint) {
        id = point.id
        sequence = point.sequence
        latitude = point.latitude
        longitude = point.longitude
        timestamp = point.timestamp
        horizontalAccuracy = point.horizontalAccuracy
        systemSpeedMetersPerSecond = point.systemSpeedMetersPerSecond
        altitudeMeters = point.altitudeMeters
        verticalAccuracyMeters = point.verticalAccuracyMeters
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
            altitudeMeters: altitudeMeters,
            verticalAccuracyMeters: verticalAccuracyMeters,
            segmentIndex: segmentIndex
        )
    }
}
