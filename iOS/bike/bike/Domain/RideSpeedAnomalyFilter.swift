import CoreLocation
import Foundation

enum RideSpeedAnomalyConfiguration {
    static let contextualHighSpeedMetersPerSecond = 40.0 / 3.6
    static let neighborDropMetersPerSecond = 10.0 / 3.6
    static let minimumSpikeAccelerationMetersPerSecondSquared = 3.0
}

enum RideSpeedAnomalyFilter {
    struct StreamingState: Hashable, Sendable {
        private var window: [TrackPoint] = []
        private var evaluatedThroughSequence: Int?

        mutating func consume(_ point: TrackPoint) -> Double? {
            window.append(point)
            guard window.count == 3 else { return nil }

            let previous = window[0]
            let candidate = window[1]
            let next = window[2]
            evaluatedThroughSequence = candidate.sequence
            window.removeFirst()
            return RideSpeedAnomalyFilter.validSpeed(for: candidate, previous: previous, next: next)
        }

        mutating func finish() -> [Double] {
            defer {
                window.removeAll()
                evaluatedThroughSequence = nil
            }

            return window.compactMap { point in
                if let evaluatedThroughSequence, point.sequence <= evaluatedThroughSequence {
                    return nil
                }
                return RideSpeedAnomalyFilter.validSpeed(for: point, previous: nil, next: nil)
            }
        }
    }

    static func maximumValidSpeed(points: [TrackPoint]) -> Double {
        let sortedPoints = points.sorted { $0.sequence < $1.sequence }
        guard !sortedPoints.isEmpty else { return 0 }
        return sortedPoints.indices.reduce(0) { maximumSpeed, index in
            let previous = index > sortedPoints.startIndex
                ? sortedPoints[sortedPoints.index(before: index)]
                : nil
            let next = index < sortedPoints.index(before: sortedPoints.endIndex)
                ? sortedPoints[sortedPoints.index(after: index)]
                : nil
            let speed = validSpeed(for: sortedPoints[index], previous: previous, next: next) ?? 0
            return max(maximumSpeed, speed)
        }
    }

    static func validSpeed(for point: TrackPoint, previous: TrackPoint?, next: TrackPoint?) -> Double? {
        guard let speedMetersPerSecond = validStoredSpeed(point.systemSpeedMetersPerSecond) else {
            return nil
        }
        guard speedMetersPerSecond >= RideSpeedAnomalyConfiguration.contextualHighSpeedMetersPerSecond else {
            return speedMetersPerSecond
        }
        guard let previous, let next,
              previous.segmentIndex == point.segmentIndex,
              next.segmentIndex == point.segmentIndex,
              point.timestamp > previous.timestamp,
              next.timestamp > point.timestamp else {
            return speedMetersPerSecond
        }
        guard isContextualSpike(point: point, previous: previous, next: next) else {
            return speedMetersPerSecond
        }
        return nil
    }

    private static func validStoredSpeed(_ speedMetersPerSecond: Double?) -> Double? {
        guard let speedMetersPerSecond,
              speedMetersPerSecond.isFinite,
              speedMetersPerSecond >= 0,
              speedMetersPerSecond <= LocationValidationConfiguration.maximumSpeedMetersPerSecond else {
            return nil
        }
        return speedMetersPerSecond
    }

    private static func isContextualSpike(point: TrackPoint, previous: TrackPoint, next: TrackPoint) -> Bool {
        let previousSpeed = previous.systemSpeedMetersPerSecond ?? 0
        let nextSpeed = next.systemSpeedMetersPerSecond ?? 0
        let speed = point.systemSpeedMetersPerSecond ?? 0
        let isolatedAgainstNeighbors = speed - previousSpeed >= RideSpeedAnomalyConfiguration.neighborDropMetersPerSecond
            && speed - nextSpeed >= RideSpeedAnomalyConfiguration.neighborDropMetersPerSecond

        let previousInterval = point.timestamp.timeIntervalSince(previous.timestamp)
        let nextInterval = next.timestamp.timeIntervalSince(point.timestamp)
        let accelerationSpike = previousInterval > 0
            && nextInterval > 0
            && (speed - previousSpeed) / previousInterval >= RideSpeedAnomalyConfiguration.minimumSpikeAccelerationMetersPerSecondSquared
            && (speed - nextSpeed) / nextInterval >= RideSpeedAnomalyConfiguration.minimumSpikeAccelerationMetersPerSecondSquared

        return isolatedAgainstNeighbors || accelerationSpike || isHighSpeedBacktrack(point: point, previous: previous, next: next)
    }

    private static func isHighSpeedBacktrack(point: TrackPoint, previous: TrackPoint, next: TrackPoint) -> Bool {
        let previousInterval = point.timestamp.timeIntervalSince(previous.timestamp)
        let nextInterval = next.timestamp.timeIntervalSince(point.timestamp)
        guard previousInterval > 0, nextInterval > 0 else { return false }

        let previousDistance = point.location.distance(from: previous.location)
        let nextDistance = next.location.distance(from: point.location)
        let previousDerivedSpeed = previousDistance / previousInterval
        let nextDerivedSpeed = nextDistance / nextInterval
        guard previousDerivedSpeed >= RideSpeedAnomalyConfiguration.contextualHighSpeedMetersPerSecond,
              nextDerivedSpeed >= RideSpeedAnomalyConfiguration.contextualHighSpeedMetersPerSecond else {
            return false
        }

        let incoming = vector(from: previous, to: point)
        let outgoing = vector(from: point, to: next)
        return incoming.x * outgoing.x + incoming.y * outgoing.y < 0
    }

    private static func vector(from start: TrackPoint, to end: TrackPoint) -> (x: Double, y: Double) {
        let meanLatitude = (start.latitude + end.latitude) / 2 * .pi / 180
        return (
            x: (end.longitude - start.longitude) * cos(meanLatitude) * 111_320,
            y: (end.latitude - start.latitude) * 110_540
        )
    }
}

private extension TrackPoint {
    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
