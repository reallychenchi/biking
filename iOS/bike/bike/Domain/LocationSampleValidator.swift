import CoreLocation
import Foundation

enum LocationValidationConfiguration {
    static let maximumHorizontalAccuracyMeters = 50.0
    static let speedFreshnessInterval: TimeInterval = 5.0
    static let segmentGapInterval: TimeInterval = 30.0
    static let maximumSpeedMetersPerSecond = 33.33
}

enum LocationRejectionReason: Equatable, Sendable {
    case invalidCoordinate
    case invalidHorizontalAccuracy
    case nonIncreasingTimestamp
}

struct AcceptedLocationSample: Equatable, Sendable {
    let point: TrackPoint
    let distanceFromPreviousMeters: Double
    let startedNewSegment: Bool
    let discardedDriftSegment: Bool
}

enum LocationValidationResult: Equatable, Sendable {
    case accepted(AcceptedLocationSample)
    case rejected(LocationRejectionReason)
}

struct LocationSampleValidator: Sendable {
    private(set) var previousPoint: TrackPoint?
    private(set) var segmentIndex = 0
    private(set) var nextSequence = 0

    mutating func validate(_ sample: RawLocationSample) -> LocationValidationResult {
        let coordinate = CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            return .rejected(.invalidCoordinate)
        }
        guard sample.horizontalAccuracy >= 0,
              sample.horizontalAccuracy <= LocationValidationConfiguration.maximumHorizontalAccuracyMeters else {
            return .rejected(.invalidHorizontalAccuracy)
        }
        if let previousPoint, sample.timestamp <= previousPoint.timestamp {
            return .rejected(.nonIncreasingTimestamp)
        }

        let validSystemSpeed: Double?
        if sample.systemSpeedMetersPerSecond >= 0,
           sample.systemSpeedMetersPerSecond <= LocationValidationConfiguration.maximumSpeedMetersPerSecond {
            validSystemSpeed = sample.systemSpeedMetersPerSecond
        } else {
            validSystemSpeed = nil
        }

        var distance = 0.0
        var startsNewSegment = previousPoint == nil
        var driftDiscarded = false

        if let previousPoint {
            let interval = sample.timestamp.timeIntervalSince(previousPoint.timestamp)
            if interval > LocationValidationConfiguration.segmentGapInterval {
                segmentIndex += 1
                startsNewSegment = true
            } else {
                let previousLocation = CLLocation(
                    latitude: previousPoint.latitude,
                    longitude: previousPoint.longitude
                )
                let currentLocation = CLLocation(latitude: sample.latitude, longitude: sample.longitude)
                let candidateDistance = currentLocation.distance(from: previousLocation)
                let derivedSpeed = interval > 0 ? candidateDistance / interval : .infinity

                if derivedSpeed > LocationValidationConfiguration.maximumSpeedMetersPerSecond {
                    segmentIndex += 1
                    startsNewSegment = true
                    driftDiscarded = true
                } else {
                    distance = candidateDistance
                }
            }
        }

        let point = TrackPoint(
            id: UUID(),
            sequence: nextSequence,
            latitude: sample.latitude,
            longitude: sample.longitude,
            timestamp: sample.timestamp,
            horizontalAccuracy: sample.horizontalAccuracy,
            systemSpeedMetersPerSecond: driftDiscarded ? nil : validSystemSpeed,
            segmentIndex: segmentIndex
        )
        nextSequence += 1
        previousPoint = point

        return .accepted(
            AcceptedLocationSample(
                point: point,
                distanceFromPreviousMeters: distance,
                startedNewSegment: startsNewSegment,
                discardedDriftSegment: driftDiscarded
            )
        )
    }

    static func freshSpeed(
        metersPerSecond: Double?,
        sampleDate: Date?,
        now: Date
    ) -> Double {
        guard let metersPerSecond, let sampleDate,
              now.timeIntervalSince(sampleDate) <= LocationValidationConfiguration.speedFreshnessInterval,
              now >= sampleDate else {
            return 0
        }
        return metersPerSecond
    }
}
