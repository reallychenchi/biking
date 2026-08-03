import CoreLocation
import Foundation
import SwiftData
import Testing
import UIKit
@testable import bike

@MainActor
struct bikeTests {
    @Test
    func mapCoordinateConverterUsesGCJ02OnlyWithinMainlandChina() {
        let beijingWGS84 = CLLocationCoordinate2D(latitude: 39.908_823, longitude: 116.397_47)
        let beijingGCJ02 = MapCoordinateConverter.mapDisplayCoordinate(for: beijingWGS84)

        #expect(abs(beijingGCJ02.latitude - 39.910_226) < 0.000_01)
        #expect(abs(beijingGCJ02.longitude - 116.403_714) < 0.000_01)

        let sanFrancisco = CLLocationCoordinate2D(latitude: 37.334_9, longitude: -122.009_02)
        #expect(MapCoordinateConverter.mapDisplayCoordinate(for: sanFrancisco).latitude == sanFrancisco.latitude)
        #expect(MapCoordinateConverter.mapDisplayCoordinate(for: sanFrancisco).longitude == sanFrancisco.longitude)
    }

    @Test
    func validatorRejectsInvalidAccuracyAndTimestamp() {
        let start = Date(timeIntervalSince1970: 1_000)
        var validator = LocationSampleValidator()

        guard case .accepted = validator.validate(sample(at: start, accuracy: 50, speed: 2)) else {
            Issue.record("50 米边界精度应被接受")
            return
        }
        #expect(
            validator.validate(sample(at: start.addingTimeInterval(1), accuracy: 50.1, speed: 2))
                == .rejected(.invalidHorizontalAccuracy)
        )
        #expect(
            validator.validate(sample(at: start, accuracy: 10, speed: 2))
                == .rejected(.nonIncreasingTimestamp)
        )
    }

    @Test
    func validatorStartsNewSegmentsForGapsAndDrift() {
        let start = Date(timeIntervalSince1970: 2_000)
        var gapValidator = LocationSampleValidator()
        _ = gapValidator.validate(sample(at: start, longitude: 116.0))
        let gapResult = gapValidator.validate(sample(at: start.addingTimeInterval(31), longitude: 116.0001))
        guard case let .accepted(gap) = gapResult else {
            Issue.record("间隔后的有效点应被接受")
            return
        }
        #expect(gap.startedNewSegment)
        #expect(gap.distanceFromPreviousMeters == 0)
        #expect(!gap.discardedDriftSegment)

        var driftValidator = LocationSampleValidator()
        _ = driftValidator.validate(sample(at: start, longitude: 116.0))
        let driftResult = driftValidator.validate(sample(at: start.addingTimeInterval(1), longitude: 117.0))
        guard case let .accepted(drift) = driftResult else {
            Issue.record("漂移后的点应作为新轨迹段起点保留")
            return
        }
        #expect(drift.startedNewSegment)
        #expect(drift.discardedDriftSegment)
        #expect(drift.distanceFromPreviousMeters == 0)
        #expect(drift.point.systemSpeedMetersPerSecond == nil)
    }

    @Test
    func validatorFiltersSpeedAndExpiresCurrentSpeed() {
        let now = Date(timeIntervalSince1970: 3_000)
        var validator = LocationSampleValidator()
        let result = validator.validate(
            sample(at: now, speed: 33.34, altitude: 123, verticalAccuracy: 4)
        )
        guard case let .accepted(accepted) = result else {
            Issue.record("位置点本身应有效")
            return
        }
        #expect(accepted.point.systemSpeedMetersPerSecond == nil)
        #expect(accepted.point.altitudeMeters == 123)
        #expect(accepted.point.verticalAccuracyMeters == 4)
        #expect(LocationSampleValidator.freshSpeed(metersPerSecond: 3, sampleDate: now, now: now.addingTimeInterval(5)) == 3)
        #expect(LocationSampleValidator.freshSpeed(metersPerSecond: 3, sampleDate: now, now: now.addingTimeInterval(5.01)) == 0)
    }

    @Test
    func metricsAndFormattingUseRequiredUnits() {
        #expect(RideMetrics.speed(distanceMeters: 1_000, durationSeconds: 0) == 0)
        #expect(RideMetrics.speed(distanceMeters: 1_000, durationSeconds: 500) == 2)
        #expect(RideMetrics.speed(distanceMeters: 1_000, durationSeconds: 400) == 2.5)
        #expect(RideFormatting.distance(1_234) == "1.23 km")
        #expect(RideFormatting.distanceCardValue(300_000) == "300.0")
        #expect(RideFormatting.distanceCardValue(25_550) == "25.55")
        #expect(RideFormatting.distanceCardValue(7_980) == "\u{2007}7.98")
        #expect(RideFormatting.distanceCardValue(1_230) == "\u{2007}1.23")
        #expect(RideFormatting.speed(10) == "36.00 km/h")
        #expect(RideFormatting.speedCardValue(83.333_333) == "300.0")
        #expect(RideFormatting.speedCardValue(7.097_222) == "25.55")
        #expect(RideFormatting.speedCardValue(2.216_667) == "\u{2007}7.98")
        #expect(RideFormatting.liveDuration(3_599) == "59:59")
        #expect(RideFormatting.liveDuration(3_600) == "01:00:00")
        #expect(RideFormatting.fullDuration(65) == "00:01:05")
        #expect(RideFormatting.hourMinuteDuration(65) == "00:01")
        #expect(RideFormatting.hourMinuteDuration(3_661) == "01:01")
        #expect(RideFormatting.elevation(123.4) == "123 m")
        #expect(RideFormatting.elevationValue(123.4) == "123")
        #expect(RideFormatting.elevationCardValue(123.4) == "\u{2007}123")
        #expect(RideFormatting.elevationCardValue(7.6) == "\u{2007}\u{2007}\u{2007}8")
        #expect(RideFormatting.elevation(nil) == "—")
        #expect(RideFormatting.elevationValue(nil) == nil)
        #expect(RideFormatting.elevationCardValue(nil) == nil)
        #expect(RideFormatting.elevationRange(minimumMeters: -12.4, maximumMeters: 85.4) == "−12–85 m")
        #expect(RideFormatting.elevationRangeValue(minimumMeters: -12.4, maximumMeters: 85.4) == "−12–85")
        #expect(RideFormatting.elevationRangeValue(minimumMeters: nil, maximumMeters: 85.4) == nil)
    }

    @Test
    func elevationAccumulatorCountsGradualAscentAndDescent() {
        let ascent = elevationMetrics([100, 101, 102, 103, 104])
        #expect(ascent.cumulativeAscentMeters == 4)
        #expect(ascent.cumulativeDescentMeters == 0)
        #expect(ascent.minimumAltitudeMeters == 100)
        #expect(ascent.maximumAltitudeMeters == 104)

        let descent = elevationMetrics([104, 103, 102, 101, 100])
        #expect(descent.cumulativeAscentMeters == 0)
        #expect(descent.cumulativeDescentMeters == 4)
    }

    @Test
    func elevationAccumulatorSuppressesFlatNoiseAndIsolatedSpike() {
        let flat = elevationMetrics([100, 101.5, 99.5, 100.8, 100])
        #expect(flat.cumulativeAscentMeters == 0)
        #expect(flat.cumulativeDescentMeters == 0)
        #expect(flat.minimumAltitudeMeters == 100)
        #expect(flat.maximumAltitudeMeters == 100.8)

        let spike = elevationMetrics([100, 130, 100])
        #expect(spike.cumulativeAscentMeters == 0)
        #expect(spike.cumulativeDescentMeters == 0)
        #expect(spike.minimumAltitudeMeters == 100)
        #expect(spike.maximumAltitudeMeters == 100)
    }

    @Test
    func elevationAccumulatorCommitsReversalsAndFinalTrendOnce() {
        var accumulator = ElevationAccumulator()
        let altitudes = [100.0, 101, 103, 105, 105, 103, 100]
        for (sequence, altitude) in altitudes.enumerated() {
            accumulator.consume(elevationPoint(sequence: sequence, altitude: altitude))
        }

        let first = accumulator.metrics()
        let second = accumulator.metrics()
        #expect(first.cumulativeAscentMeters == 5)
        #expect(first.cumulativeDescentMeters == 5)
        #expect(first == second)
    }

    @Test
    func elevationAccumulatorDoesNotCrossSegmentsOrLongGaps() {
        var segmented = ElevationAccumulator()
        segmented.consume(elevationPoint(sequence: 0, altitude: 100, segmentIndex: 0))
        segmented.consume(elevationPoint(sequence: 1, altitude: 105, segmentIndex: 0))
        segmented.consume(elevationPoint(sequence: 2, altitude: 80, segmentIndex: 1))
        segmented.consume(elevationPoint(sequence: 3, altitude: 90, segmentIndex: 1))
        #expect(segmented.metrics().cumulativeAscentMeters == 15)
        #expect(segmented.metrics().cumulativeDescentMeters == 0)

        var gap = ElevationAccumulator()
        let start = Date(timeIntervalSince1970: 10_000)
        gap.consume(elevationPoint(sequence: 0, altitude: 100, date: start))
        gap.consume(elevationPoint(sequence: 1, altitude: 105, date: start.addingTimeInterval(1)))
        gap.consume(elevationPoint(sequence: 2, altitude: 50, date: start.addingTimeInterval(32)))
        gap.consume(elevationPoint(sequence: 3, altitude: 60, date: start.addingTimeInterval(33)))
        #expect(gap.metrics().cumulativeAscentMeters == 15)
        #expect(gap.metrics().cumulativeDescentMeters == 0)
    }

    @Test
    func elevationAccumulatorDistinguishesUnavailableFromZero() {
        var unavailable = ElevationAccumulator()
        unavailable.consume(elevationPoint(sequence: 0, altitude: 100, verticalAccuracy: 20.1))
        #expect(unavailable.metrics() == ElevationMetrics(
            cumulativeAscentMeters: nil,
            cumulativeDescentMeters: nil,
            minimumAltitudeMeters: nil,
            maximumAltitudeMeters: nil
        ))

        var onePoint = ElevationAccumulator()
        onePoint.consume(elevationPoint(sequence: 0, altitude: -10))
        #expect(onePoint.metrics().cumulativeAscentMeters == nil)
        #expect(onePoint.metrics().minimumAltitudeMeters == -10)
        #expect(onePoint.metrics().maximumAltitudeMeters == -10)

        let belowThreshold = elevationMetrics([100, 102])
        #expect(belowThreshold.cumulativeAscentMeters == 0)
        #expect(belowThreshold.cumulativeDescentMeters == 0)

        let exactThreshold = elevationMetrics([100, 103])
        #expect(exactThreshold.cumulativeAscentMeters == 3)
    }

    @Test
    func routeGeometrySortsPointsAndPreservesSegmentBreaks() {
        let start = Date(timeIntervalSince1970: 3_500)
        let points = [
            trackPoint(sequence: 2, longitude: 116.002, segmentIndex: 1, date: start.addingTimeInterval(2)),
            trackPoint(sequence: 0, longitude: 116.000, segmentIndex: 0, date: start),
            trackPoint(sequence: 1, longitude: 116.001, segmentIndex: 0, date: start.addingTimeInterval(1))
        ]

        let geometry = RideRouteGeometry(points: points)

        #expect(geometry.segments.count == 2)
        #expect(geometry.segments[0].map(\.longitude) == [116.000, 116.001])
        #expect(geometry.segments[1].map(\.longitude) == [116.002])
        #expect(geometry.coordinates.map(\.longitude) == [116.000, 116.001, 116.002])
        #expect(geometry.mapRect != nil)
    }

    @Test
    func speedAnalysisBuildsDistanceCurveAndZoneShares() {
        let start = Date(timeIntervalSince1970: 3_600)
        let points = [
            trackPoint(
                sequence: 0,
                longitude: 116.000,
                segmentIndex: 0,
                date: start,
                speedMetersPerSecond: 2
            ),
            trackPoint(
                sequence: 1,
                longitude: 116.001,
                segmentIndex: 0,
                date: start.addingTimeInterval(1),
                speedMetersPerSecond: 4
            ),
            trackPoint(
                sequence: 2,
                longitude: 116.002,
                segmentIndex: 0,
                date: start.addingTimeInterval(2),
                speedMetersPerSecond: nil
            ),
            trackPoint(
                sequence: 3,
                longitude: 116.003,
                segmentIndex: 0,
                date: start.addingTimeInterval(3),
                speedMetersPerSecond: 6
            ),
            trackPoint(
                sequence: 4,
                longitude: 116.004,
                segmentIndex: 1,
                date: start.addingTimeInterval(4),
                speedMetersPerSecond: 8
            )
        ]

        let analysis = RideSpeedAnalysis(points: points)

        #expect(analysis.chartPoints.map(\.sequence) == [0, 1, 3, 4])
        #expect(analysis.chartPoints.map(\.seriesIndex) == [0, 0, 1, 2])
        #expect(analysis.totalDistanceMeters > 0)
        #expect(analysis.classifiedDistanceMeters > 0)
        #expect(analysis.unclassifiedDistanceMeters > 0)

        let tenToFifteen = analysis.zoneShares.first { $0.zone.id == 1 }
        let twentyToTwentyFive = analysis.zoneShares.first { $0.zone.id == 3 }
        #expect(abs((tenToFifteen?.proportion ?? 0) - 0.5) < 0.001)
        #expect(abs((twentyToTwentyFive?.proportion ?? 0) - 0.5) < 0.001)
    }

    @Test
    func speedAnalysisUsesFixedInclusiveLowerZoneBounds() {
        let start = Date(timeIntervalSince1970: 3_700)
        let points = [
            trackPoint(
                sequence: 0,
                longitude: 116.000,
                segmentIndex: 0,
                date: start,
                speedMetersPerSecond: 2
            ),
            trackPoint(
                sequence: 1,
                longitude: 116.001,
                segmentIndex: 0,
                date: start.addingTimeInterval(1),
                speedMetersPerSecond: 10 / 3.6
            ),
            trackPoint(
                sequence: 2,
                longitude: 116.002,
                segmentIndex: 0,
                date: start.addingTimeInterval(2),
                speedMetersPerSecond: 30 / 3.6
            )
        ]

        let analysis = RideSpeedAnalysis(points: points)

        #expect(analysis.zoneShares.first { $0.zone.id == 0 }?.distanceMeters == 0)
        #expect((analysis.zoneShares.first { $0.zone.id == 1 }?.distanceMeters ?? 0) > 0)
        #expect((analysis.zoneShares.first { $0.zone.id == 5 }?.distanceMeters ?? 0) > 0)
    }

    @Test
    func externalSpeedZoneLabelsMoveAwayFromCenterAndKeepMinimumSpacing() {
        let spacing: CGFloat = 14
        let centerY: CGFloat = 100
        let naturalPositions: [CGFloat] = [90, 95, 105, 110]
        let positions = OutwardVerticalLabelLayout.positions(
            naturalYPositions: naturalPositions,
            centerY: centerY,
            spacing: spacing
        )

        #expect(positions.count == naturalPositions.count)
        for pair in zip(positions, positions.dropFirst()) {
            #expect(pair.1 - pair.0 >= spacing)
        }
        #expect(positions[0] <= naturalPositions[0])
        #expect(positions[1] <= naturalPositions[1])
        #expect(positions[2] >= naturalPositions[2])
        #expect(positions[3] >= naturalPositions[3])
    }

    @Test
    func speedZoneChartGeometryExpandsAroundFixedCircleCenter() {
        let geometry = SpeedZoneChartGeometry.make(
            baseHeight: 240,
            labelYPositions: [-10, 260],
            verticalMargin: 14
        )

        #expect(geometry.height == 298)
        #expect(geometry.centerY == 144)
    }

    @Test
    func externalSpeedZoneLeaderUsesRadialThenHorizontalGeometry() {
        let center = CGPoint(x: 150, y: 120)
        let angle = -Double.pi / 4
        let labelY: CGFloat = 40
        let elbow = RadialLeaderGeometry.elbow(
            center: center,
            outerRadius: 70,
            minimumLength: 10,
            angle: angle,
            labelY: labelY
        )
        let vector = CGVector(dx: elbow.x - center.x, dy: elbow.y - center.y)
        let crossProduct = vector.dx * CGFloat(sin(angle))
            - vector.dy * CGFloat(cos(angle))
        let dotProduct = vector.dx * CGFloat(cos(angle))
            + vector.dy * CGFloat(sin(angle))

        #expect(abs(elbow.y - labelY) < 0.001)
        #expect(abs(crossProduct) < 0.001)
        #expect(dotProduct >= 80)
    }

    @Test
    func routeSnapshotDiskCachePersistsData() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let cache = RideRouteSnapshotDiskCache(directoryURL: directoryURL)
        let expectedData = Data([0x01, 0x02, 0x03])

        #expect(try await cache.data(forKey: "ride") == nil)
        try await cache.store(expectedData, forKey: "ride")
        #expect(try await cache.data(forKey: "ride") == expectedData)
    }

    @Test
    func snapshotRendererCacheKeyFormatIsStable() {
        let rideID = UUID(uuidString: "12345678-1234-1234-1234-123456789012")!
        let updatedAt = Date(timeIntervalSince1970: 1_000)
        let size = CGSize(width: 92, height: 92)
        let key = RideRouteSnapshotRenderer.cacheKey(
            rideID: rideID,
            updatedAt: updatedAt,
            size: size,
            scale: 3,
            appearance: .light
        )
        #expect(key == "v5-light-12345678-1234-1234-1234-123456789012-1000000-92x92-@3x")
    }

    @Test
    func snapshotRendererDiskCacheHitSkipsLoader() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let rideID = UUID()
        let updatedAt = Date(timeIntervalSince1970: 10_000)
        let size = CGSize(width: 92, height: 92)
        let scale = UIScreen.main.scale

        let imgRenderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = imgRenderer.image { context in
            context.cgContext.setFillColor(UIColor.red.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        guard let pngData = image.pngData() else {
            Issue.record("Failed to create test PNG")
            return
        }

        let diskCache = RideRouteSnapshotDiskCache(directoryURL: directoryURL)
        let cacheKey = RideRouteSnapshotRenderer.cacheKey(
            rideID: rideID,
            updatedAt: updatedAt,
            size: size,
            scale: scale,
            appearance: .light
        )
        try await diskCache.store(pngData, forKey: cacheKey)

        let renderer = RideRouteSnapshotRenderer(diskCache: diskCache)
        var loaderCallCount = 0

        let first = try await renderer.rendering(
            rideID: rideID,
            updatedAt: updatedAt,
            size: size,
            appearance: .light,
            loadPoints: { loaderCallCount += 1; return [] }
        )
        guard case .image = first else {
            Issue.record("Expected .image from disk cache hit, got \(first)")
            return
        }
        #expect(loaderCallCount == 0)

        let second = try await renderer.rendering(
            rideID: rideID,
            updatedAt: updatedAt,
            size: size,
            appearance: .light,
            loadPoints: { loaderCallCount += 1; return [] }
        )
        guard case .image = second else {
            Issue.record("Expected .image from memory cache hit")
            return
        }
        #expect(loaderCallCount == 0)
    }

    @Test
    func snapshotRendererEmptyPointsReturnsEmpty() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let diskCache = RideRouteSnapshotDiskCache(directoryURL: directoryURL)
        let renderer = RideRouteSnapshotRenderer(diskCache: diskCache)

        let result = try await renderer.rendering(
            rideID: UUID(),
            updatedAt: Date(),
            size: CGSize(width: 92, height: 92),
            appearance: .light,
            loadPoints: { [] }
        )
        guard case .empty = result else {
            Issue.record("Expected .empty for zero points, got \(result)")
            return
        }
    }

    @Test
    func snapshotRendererCacheMissLoaderErrorPropagates() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let diskCache = RideRouteSnapshotDiskCache(directoryURL: directoryURL)
        let renderer = RideRouteSnapshotRenderer(diskCache: diskCache)
        let missingID = UUID()

        await #expect(throws: RideRepositoryError.self) {
            _ = try await renderer.rendering(
                rideID: UUID(),
                updatedAt: Date(),
                size: CGSize(width: 92, height: 92),
                appearance: .light,
                loadPoints: { throw RideRepositoryError.rideNotFound(missingID) }
            )
        }
    }

    @Test
    func movementTimeUsesHysteresisAndStopsForStaleSpeed() {
        var accumulator = MovementTimeAccumulator()

        accumulator.consume(speedMetersPerSecond: 0.7, at: 1)
        #expect(accumulator.elapsed(at: 2) == 0)

        accumulator.consume(speedMetersPerSecond: 0.8, at: 2)
        accumulator.consume(speedMetersPerSecond: 0.5, at: 4)
        #expect(accumulator.elapsed(at: 6) == 4)

        accumulator.consume(speedMetersPerSecond: 0.3, at: 7)
        #expect(accumulator.elapsed(at: 10) == 5)

        accumulator.consume(speedMetersPerSecond: 2, at: 12)
        #expect(accumulator.elapsed(at: 30) == 10)
        #expect(!accumulator.isMoving)
    }

    @Test
    func invalidSpeedStopsMovementWithoutExceedingTotalTime() {
        var accumulator = MovementTimeAccumulator()
        accumulator.consume(speedMetersPerSecond: 2, at: 1)
        accumulator.consume(speedMetersPerSecond: nil, at: 4)

        #expect(accumulator.elapsed(at: 20) == 3)
        #expect(!accumulator.isMoving)
    }

    @Test
    func swiftDataRepositoryCompletesRide() async throws {
        let container = try ModelContainer(
            for: RideEntity.self,
            TrackPointEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = SwiftDataRideRepository(modelContainer: container)
        let rideID = UUID()
        let start = Date(timeIntervalSince1970: 4_000)
        let point = TrackPoint(
            id: UUID(),
            sequence: 0,
            latitude: 39.9,
            longitude: 116.4,
            timestamp: start,
            horizontalAccuracy: 5,
            systemSpeedMetersPerSecond: 4,
            altitudeMeters: 100,
            verticalAccuracyMeters: 5,
            segmentIndex: 0
        )
        let progress = RideProgress(
            totalElapsedSeconds: 100,
            movingElapsedSeconds: 80,
            distanceMeters: 500,
            maximumSpeedMetersPerSecond: 6,
            overallSpeedMetersPerSecond: 5,
            averageSpeedMetersPerSecond: 6.25,
            cumulativeAscentMeters: 12,
            cumulativeDescentMeters: 8,
            minimumAltitudeMeters: 100,
            maximumAltitudeMeters: 112,
            updatedAt: start.addingTimeInterval(100)
        )

        try await repository.createTemporaryRide(id: rideID, startDate: start, createdAt: start)
        #expect(try await repository.unfinishedRideIDs() == [rideID])
        let completion = RideCompletionSnapshot(
            rideID: rideID,
            endDate: start.addingTimeInterval(100),
            progress: progress
        )
        try await repository.completeRide(completion, pendingPoints: [point])
        try await repository.completeRide(completion, pendingPoints: [point])

        let summaries = try await repository.completedRideSummaries()
        #expect(summaries.count == 1)
        #expect(summaries.first?.distanceMeters == 500)
        #expect(summaries.first?.averageSpeedMetersPerSecond == 6.25)
        #expect(try await repository.unfinishedRideIDs().isEmpty)

        let record = try await repository.completedRide(id: rideID)
        #expect(record.status == .completed)
        #expect(record.distanceMeters == 500)
        #expect(record.totalElapsedSeconds == 100)
        #expect(record.movingElapsedSeconds == 80)
        #expect(record.overallSpeedMetersPerSecond == 5)
        #expect(record.averageSpeedMetersPerSecond == 6.25)
        #expect(record.cumulativeAscentMeters == 12)
        #expect(record.cumulativeDescentMeters == 8)
        #expect(record.minimumAltitudeMeters == 100)
        #expect(record.maximumAltitudeMeters == 112)
        #expect(record.points == [point])
    }

    @Test
    func completedRideSummariesFiltersAndSorts() async throws {
        let container = try ModelContainer(
            for: RideEntity.self,
            TrackPointEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = SwiftDataRideRepository(modelContainer: container)

        let earlyStart = Date(timeIntervalSince1970: 1_000)
        let lateStart = Date(timeIntervalSince1970: 2_000)
        let progress = RideProgress(
            totalElapsedSeconds: 60,
            movingElapsedSeconds: 50,
            distanceMeters: 300,
            maximumSpeedMetersPerSecond: 5,
            overallSpeedMetersPerSecond: 4,
            averageSpeedMetersPerSecond: 3.5,
            cumulativeAscentMeters: nil,
            cumulativeDescentMeters: nil,
            minimumAltitudeMeters: nil,
            maximumAltitudeMeters: nil,
            updatedAt: lateStart
        )

        let earlyID = UUID()
        let lateID = UUID()
        let recordingID = UUID()

        try await repository.createTemporaryRide(id: earlyID, startDate: earlyStart, createdAt: earlyStart)
        try await repository.completeRide(
            RideCompletionSnapshot(rideID: earlyID, endDate: earlyStart.addingTimeInterval(60), progress: progress),
            pendingPoints: []
        )

        try await repository.createTemporaryRide(id: lateID, startDate: lateStart, createdAt: lateStart)
        try await repository.completeRide(
            RideCompletionSnapshot(rideID: lateID, endDate: lateStart.addingTimeInterval(60), progress: progress),
            pendingPoints: []
        )

        try await repository.createTemporaryRide(id: recordingID, startDate: lateStart, createdAt: lateStart)

        let summaries = try await repository.completedRideSummaries()
        #expect(summaries.count == 2)
        #expect(summaries[0].id == lateID)
        #expect(summaries[1].id == earlyID)
        #expect(summaries[0].distanceMeters == 300)
        #expect(summaries[0].averageSpeedMetersPerSecond == 3.5)
    }

    @Test
    func completedRideByIDReturnsSortedPoints() async throws {
        let container = try ModelContainer(
            for: RideEntity.self,
            TrackPointEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = SwiftDataRideRepository(modelContainer: container)

        let start = Date(timeIntervalSince1970: 5_000)
        let rideID = UUID()
        let point0 = TrackPoint(
            id: UUID(), sequence: 0, latitude: 39.9, longitude: 116.4,
            timestamp: start, horizontalAccuracy: 5, systemSpeedMetersPerSecond: 3, segmentIndex: 0
        )
        let point1 = TrackPoint(
            id: UUID(), sequence: 1, latitude: 39.91, longitude: 116.41,
            timestamp: start.addingTimeInterval(5), horizontalAccuracy: 5, systemSpeedMetersPerSecond: 3, segmentIndex: 0
        )
        let progress = RideProgress(
            totalElapsedSeconds: 10, movingElapsedSeconds: 10, distanceMeters: 100,
            maximumSpeedMetersPerSecond: 3, overallSpeedMetersPerSecond: 3, averageSpeedMetersPerSecond: 3,
            cumulativeAscentMeters: nil, cumulativeDescentMeters: nil,
            minimumAltitudeMeters: nil, maximumAltitudeMeters: nil,
            updatedAt: start.addingTimeInterval(10)
        )

        try await repository.createTemporaryRide(id: rideID, startDate: start, createdAt: start)
        try await repository.completeRide(
            RideCompletionSnapshot(rideID: rideID, endDate: start.addingTimeInterval(10), progress: progress),
            pendingPoints: [point1, point0]
        )

        let record = try await repository.completedRide(id: rideID)
        #expect(record.points.count == 2)
        #expect(record.points[0].sequence == 0)
        #expect(record.points[1].sequence == 1)

        let missingID = UUID()
        await #expect(throws: RideRepositoryError.self) {
            _ = try await repository.completedRide(id: missingID)
        }
    }

    @Test
    func rideLibraryReloadOnlyCallsSummaryAPI() async {
        let repository = FakeRideRepository()
        let library = await RideLibrary(repository: repository)
        await library.reload()
        #expect(await repository.summaryCallCount() == 1)
        #expect(await repository.detailCallCount() == 0)
    }

    @Test
    func controllerBlocksDeniedAuthorization() async {
        let repository = FakeRideRepository()
        let tracking = FakeTrackingService(readiness: .denied)
        let controller = RideSessionController(repository: repository, trackingService: tracking)

        await controller.startRide()

        #expect(controller.phase == .idle)
        #expect(controller.notice?.offersSettings == true)
        #expect(await repository.createdRideCount() == 0)
    }

    @Test
    func controllerDiscardsShortRideWithNotice() async {
        let repository = FakeRideRepository()
        let tracking = FakeTrackingService(readiness: .ready)
        let controller = RideSessionController(repository: repository, trackingService: tracking)

        await controller.startRide()
        #expect(controller.phase == .recording)
        await controller.endRide()

        #expect(controller.phase == .idle)
        #expect(controller.notice?.title == "骑行时间太短")
        #expect(await repository.completedRideCount() == 0)
        #expect(await repository.deletedRideCount() == 1)
    }

    @Test
    func controllerKeepsFailedCompletionForRetry() async {
        let repository = FakeRideRepository()
        await repository.setCompletionFailure(true)
        let tracking = FakeTrackingService(readiness: .ready)
        let controller = RideSessionController(repository: repository, trackingService: tracking)

        await controller.startRide()
        #expect(controller.phase == .recording)
        await controller.endRide()
        #expect(controller.phase == .saveFailed)

        await repository.setCompletionFailure(false)
        await controller.retrySaving()
        #expect(controller.phase == .idle)
        #expect(await repository.completedRideCount() == 1)
    }

    private func sample(
        at date: Date,
        longitude: Double = 116.4,
        accuracy: Double = 5,
        speed: Double = 2,
        altitude: Double? = nil,
        verticalAccuracy: Double? = nil
    ) -> RawLocationSample {
        RawLocationSample(
            latitude: 39.9,
            longitude: longitude,
            timestamp: date,
            horizontalAccuracy: accuracy,
            systemSpeedMetersPerSecond: speed,
            altitudeMeters: altitude,
            verticalAccuracyMeters: verticalAccuracy
        )
    }

    private func trackPoint(
        sequence: Int,
        longitude: Double,
        segmentIndex: Int,
        date: Date,
        speedMetersPerSecond: Double? = 2
    ) -> TrackPoint {
        TrackPoint(
            id: UUID(),
            sequence: sequence,
            latitude: 39.9,
            longitude: longitude,
            timestamp: date,
            horizontalAccuracy: 5,
            systemSpeedMetersPerSecond: speedMetersPerSecond,
            segmentIndex: segmentIndex
        )
    }

    private func elevationMetrics(_ altitudes: [Double]) -> ElevationMetrics {
        var accumulator = ElevationAccumulator()
        for (sequence, altitude) in altitudes.enumerated() {
            accumulator.consume(elevationPoint(sequence: sequence, altitude: altitude))
        }
        return accumulator.metrics()
    }

    private func elevationPoint(
        sequence: Int,
        altitude: Double,
        verticalAccuracy: Double = 5,
        segmentIndex: Int = 0,
        date: Date? = nil
    ) -> TrackPoint {
        TrackPoint(
            id: UUID(),
            sequence: sequence,
            latitude: 39.9,
            longitude: 116.4,
            timestamp: date ?? Date(timeIntervalSince1970: 10_000 + Double(sequence)),
            horizontalAccuracy: 5,
            systemSpeedMetersPerSecond: 2,
            altitudeMeters: altitude,
            verticalAccuracyMeters: verticalAccuracy,
            segmentIndex: segmentIndex
        )
    }
}

private actor FakeRideRepository: RideRepository {
    private var created = 0
    private var completed = 0
    private var deleted = 0
    private var failCompletion = false
    private var summaryCalls = 0
    private var detailCalls = 0

    func createTemporaryRide(id: UUID, startDate: Date, createdAt: Date) { created += 1 }
    func appendCheckpoint(rideID: UUID, points: [TrackPoint], progress: RideProgress) {}
    func completeRide(_ completion: RideCompletionSnapshot, pendingPoints: [TrackPoint]) throws {
        if failCompletion { throw FakeError.saveFailed }
        completed += 1
    }
    func completedRideSummaries() -> [RideSummary] {
        summaryCalls += 1
        return []
    }
    func completedRide(id: UUID) throws -> RideRecord {
        detailCalls += 1
        throw RideRepositoryError.rideNotFound(id)
    }
    func unfinishedRideIDs() -> [UUID] { [] }
    func discardUnfinishedRides() {}
    func deleteRide(id: UUID) { deleted += 1 }

    func setCompletionFailure(_ value: Bool) { failCompletion = value }
    func createdRideCount() -> Int { created }
    func completedRideCount() -> Int { completed }
    func deletedRideCount() -> Int { deleted }
    func summaryCallCount() -> Int { summaryCalls }
    func detailCallCount() -> Int { detailCalls }
}

@MainActor
private final class FakeTrackingService: RideTrackingProviding {
    let readiness: TrackingReadiness

    init(readiness: TrackingReadiness) {
        self.readiness = readiness
    }

    func prepareForRide() async -> TrackingReadiness { readiness }
    func startBackgroundActivity() {}
    func updates() -> AsyncStream<TrackingUpdate> { AsyncStream { $0.finish() } }
    func stop() {}
}

private enum FakeError: Error {
    case saveFailed
}
