import CoreLocation
import Foundation

struct RideSpeedChartPoint: Identifiable, Hashable, Sendable {
    let sequence: Int
    let seriesIndex: Int
    let cumulativeDistanceMeters: Double
    let speedMetersPerSecond: Double

    var id: Int { sequence }
}

struct RideSpeedZone: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let lowerBoundKilometersPerHour: Double
    let upperBoundKilometersPerHour: Double?

    fileprivate func contains(speedMetersPerSecond: Double) -> Bool {
        guard speedMetersPerSecond >= lowerBoundKilometersPerHour / 3.6 else { return false }
        guard let upperBoundKilometersPerHour else { return true }
        return speedMetersPerSecond < upperBoundKilometersPerHour / 3.6
    }
}

struct RideSpeedZoneShare: Identifiable, Hashable, Sendable {
    let zone: RideSpeedZone
    let distanceMeters: Double
    let proportion: Double

    var id: Int { zone.id }
}

struct RideSpeedAnalysis: Hashable, Sendable {
    static let zones = [
        RideSpeedZone(
            id: 0,
            title: "< 10 km/h",
            lowerBoundKilometersPerHour: 0,
            upperBoundKilometersPerHour: 10
        ),
        RideSpeedZone(
            id: 1,
            title: "10–15 km/h",
            lowerBoundKilometersPerHour: 10,
            upperBoundKilometersPerHour: 15
        ),
        RideSpeedZone(
            id: 2,
            title: "15–20 km/h",
            lowerBoundKilometersPerHour: 15,
            upperBoundKilometersPerHour: 20
        ),
        RideSpeedZone(
            id: 3,
            title: "20–25 km/h",
            lowerBoundKilometersPerHour: 20,
            upperBoundKilometersPerHour: 25
        ),
        RideSpeedZone(
            id: 4,
            title: "25–30 km/h",
            lowerBoundKilometersPerHour: 25,
            upperBoundKilometersPerHour: 30
        ),
        RideSpeedZone(
            id: 5,
            title: "≥ 30 km/h",
            lowerBoundKilometersPerHour: 30,
            upperBoundKilometersPerHour: nil
        )
    ]

    let chartPoints: [RideSpeedChartPoint]
    let zoneShares: [RideSpeedZoneShare]
    let totalDistanceMeters: Double
    let classifiedDistanceMeters: Double
    let unclassifiedDistanceMeters: Double

    init(points: [TrackPoint]) {
        let sortedPoints = points.sorted { $0.sequence < $1.sequence }
        var chartPoints: [RideSpeedChartPoint] = []
        var zoneDistances = Array(repeating: 0.0, count: Self.zones.count)
        var cumulativeDistanceMeters = 0.0
        var unclassifiedDistanceMeters = 0.0
        var previousPoint: TrackPoint?
        var activeSeriesIndex: Int?
        var nextSeriesIndex = 0

        for point in sortedPoints {
            let continuesSegment = previousPoint?.segmentIndex == point.segmentIndex
            var distanceFromPreviousMeters = 0.0

            if let previousPoint, continuesSegment {
                distanceFromPreviousMeters = point.location.distance(from: previousPoint.location)
                cumulativeDistanceMeters += distanceFromPreviousMeters
            } else {
                activeSeriesIndex = nil
            }

            if let speedMetersPerSecond = Self.validSpeed(point.systemSpeedMetersPerSecond) {
                if activeSeriesIndex == nil {
                    activeSeriesIndex = nextSeriesIndex
                    nextSeriesIndex += 1
                }
                chartPoints.append(
                    RideSpeedChartPoint(
                        sequence: point.sequence,
                        seriesIndex: activeSeriesIndex ?? 0,
                        cumulativeDistanceMeters: cumulativeDistanceMeters,
                        speedMetersPerSecond: speedMetersPerSecond
                    )
                )

                if continuesSegment,
                   let zoneIndex = Self.zoneIndex(for: speedMetersPerSecond) {
                    zoneDistances[zoneIndex] += distanceFromPreviousMeters
                }
            } else {
                activeSeriesIndex = nil
                if continuesSegment {
                    unclassifiedDistanceMeters += distanceFromPreviousMeters
                }
            }

            previousPoint = point
        }

        let classifiedDistanceMeters = zoneDistances.reduce(0, +)
        self.chartPoints = chartPoints
        zoneShares = zip(Self.zones, zoneDistances).map { zone, distanceMeters in
            RideSpeedZoneShare(
                zone: zone,
                distanceMeters: distanceMeters,
                proportion: classifiedDistanceMeters > 0 ? distanceMeters / classifiedDistanceMeters : 0
            )
        }
        totalDistanceMeters = cumulativeDistanceMeters
        self.classifiedDistanceMeters = classifiedDistanceMeters
        self.unclassifiedDistanceMeters = unclassifiedDistanceMeters
    }

    private static func validSpeed(_ speedMetersPerSecond: Double?) -> Double? {
        guard let speedMetersPerSecond,
              speedMetersPerSecond.isFinite,
              speedMetersPerSecond >= 0,
              speedMetersPerSecond <= LocationValidationConfiguration.maximumSpeedMetersPerSecond else {
            return nil
        }
        return speedMetersPerSecond
    }

    private static func zoneIndex(for speedMetersPerSecond: Double) -> Int? {
        zones.firstIndex { $0.contains(speedMetersPerSecond: speedMetersPerSecond) }
    }
}

private extension TrackPoint {
    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
