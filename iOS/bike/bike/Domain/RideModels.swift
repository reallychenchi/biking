import CoreLocation
import Foundation

enum RideStatus: String, Codable, Sendable {
    case recording
    case completed
}

struct TrackPoint: Identifiable, Hashable, Sendable {
    let id: UUID
    let sequence: Int
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let horizontalAccuracy: Double
    let systemSpeedMetersPerSecond: Double?
    let segmentIndex: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct RideRecord: Identifiable, Hashable, Sendable {
    let id: UUID
    let status: RideStatus
    let startDate: Date
    let endDate: Date?
    let totalElapsedSeconds: TimeInterval
    let movingElapsedSeconds: TimeInterval
    let distanceMeters: Double
    let maximumSpeedMetersPerSecond: Double
    let overallSpeedMetersPerSecond: Double
    let averageSpeedMetersPerSecond: Double
    let createdAt: Date
    let updatedAt: Date
    let points: [TrackPoint]
}

struct RideProgress: Hashable, Sendable {
    let totalElapsedSeconds: TimeInterval
    let movingElapsedSeconds: TimeInterval
    let distanceMeters: Double
    let maximumSpeedMetersPerSecond: Double
    let overallSpeedMetersPerSecond: Double
    let averageSpeedMetersPerSecond: Double
    let updatedAt: Date
}

struct RideCompletionSnapshot: Hashable, Sendable {
    let rideID: UUID
    let endDate: Date
    let progress: RideProgress
}

struct RawLocationSample: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let horizontalAccuracy: Double
    let systemSpeedMetersPerSecond: Double

    init(location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        timestamp = location.timestamp
        horizontalAccuracy = location.horizontalAccuracy
        systemSpeedMetersPerSecond = location.speed
    }

    init(
        latitude: Double,
        longitude: Double,
        timestamp: Date,
        horizontalAccuracy: Double,
        systemSpeedMetersPerSecond: Double
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
        self.systemSpeedMetersPerSecond = systemSpeedMetersPerSecond
    }
}

enum RideMetrics {
    static func speed(distanceMeters: Double, durationSeconds: TimeInterval) -> Double {
        guard durationSeconds > 0 else { return 0 }
        return max(0, distanceMeters / durationSeconds)
    }
}
