import CoreLocation
import Foundation

enum RideSpeedAnomalyConfiguration {
    static let contextualHighSpeedMetersPerSecond = 40.0 / 3.6
    static let neighborDropMetersPerSecond = 10.0 / 3.6
    static let minimumSpikeAccelerationMetersPerSecondSquared = 3.0
    static let robustMaximumSpeedWindowSeconds: TimeInterval = 5
    static let minimumRobustWindowSampleCount = 3
    static let trimmedWindowSampleCount = 5
}

enum RideSpeedAnomalyFilter {
    struct StreamingState: Hashable, Sendable {
        private var points: [TrackPoint] = []

        mutating func consume(_ point: TrackPoint) -> Double? {
            points.append(point)
            guard points.count >= RideSpeedAnomalyConfiguration.minimumRobustWindowSampleCount else {
                return nil
            }
            return RideSpeedAnomalyFilter.estimatedMaximumSpeed(points: points, includesBoundarySpeeds: false)
        }

        mutating func finish() -> [Double] {
            defer {
                points.removeAll()
            }
            let maximumSpeed = RideSpeedAnomalyFilter.estimatedMaximumSpeed(points: points)
            return maximumSpeed > 0 ? [maximumSpeed] : []
        }
    }

    static func maximumValidSpeed(points: [TrackPoint]) -> Double {
        estimatedMaximumSpeed(points: points)
    }

    static func estimatedMaximumSpeed(points: [TrackPoint]) -> Double {
        estimatedMaximumSpeed(points: points, includesBoundarySpeeds: true)
    }

    private static func estimatedMaximumSpeed(
        points: [TrackPoint],
        includesBoundarySpeeds: Bool
    ) -> Double {
        let samples = speedSamples(points: points, includesBoundarySpeeds: includesBoundarySpeeds)
        guard samples.count >= RideSpeedAnomalyConfiguration.minimumRobustWindowSampleCount else {
            return samples.map(\.speedMetersPerSecond).max() ?? 0
        }

        var maximumSpeed = 0.0
        for startIndex in samples.indices {
            var window: [SpeedSample] = []
            for sample in samples[startIndex...] {
                if sample.segmentIndex != samples[startIndex].segmentIndex {
                    break
                }
                guard sample.timestamp.timeIntervalSince(samples[startIndex].timestamp)
                    <= RideSpeedAnomalyConfiguration.robustMaximumSpeedWindowSeconds else {
                    break
                }
                window.append(sample)
                if window.count >= RideSpeedAnomalyConfiguration.minimumRobustWindowSampleCount {
                    maximumSpeed = max(maximumSpeed, robustSpeed(samples: window))
                }
            }
        }
        return maximumSpeed
    }

    private struct SpeedSample: Hashable, Sendable {
        let sequence: Int
        let timestamp: Date
        let segmentIndex: Int
        let speedMetersPerSecond: Double
    }

    private static func speedSamples(
        points: [TrackPoint],
        includesBoundarySpeeds: Bool
    ) -> [SpeedSample] {
        let sortedPoints = points.sorted { $0.sequence < $1.sequence }
        return sortedPoints.indices.compactMap { index in
            guard includesBoundarySpeeds
                    || (index > sortedPoints.startIndex && index < sortedPoints.index(before: sortedPoints.endIndex)) else {
                return nil
            }
            let previous = index > sortedPoints.startIndex
                ? sortedPoints[sortedPoints.index(before: index)]
                : nil
            let next = index < sortedPoints.index(before: sortedPoints.endIndex)
                ? sortedPoints[sortedPoints.index(after: index)]
                : nil
            guard let speed = validSpeed(for: sortedPoints[index], previous: previous, next: next) else {
                return nil
            }
            return SpeedSample(
                sequence: sortedPoints[index].sequence,
                timestamp: sortedPoints[index].timestamp,
                segmentIndex: sortedPoints[index].segmentIndex,
                speedMetersPerSecond: speed
            )
        }
    }

    private static func robustSpeed(samples: [SpeedSample]) -> Double {
        let sortedSpeeds = samples.map(\.speedMetersPerSecond).sorted()
        guard sortedSpeeds.count >= RideSpeedAnomalyConfiguration.trimmedWindowSampleCount else {
            return median(sortedSpeeds)
        }
        let trimmedSpeeds = sortedSpeeds.dropFirst().dropLast()
        return trimmedSpeeds.reduce(0, +) / Double(trimmedSpeeds.count)
    }

    private static func median(_ sortedSpeeds: [Double]) -> Double {
        guard !sortedSpeeds.isEmpty else { return 0 }
        let middleIndex = sortedSpeeds.count / 2
        if sortedSpeeds.count.isMultiple(of: 2) {
            return (sortedSpeeds[middleIndex - 1] + sortedSpeeds[middleIndex]) / 2
        }
        return sortedSpeeds[middleIndex]
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
