import Foundation
import SwiftData
import Testing
@testable import bike

@MainActor
struct bikeTests {
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
        let result = validator.validate(sample(at: now, speed: 33.34))
        guard case let .accepted(accepted) = result else {
            Issue.record("位置点本身应有效")
            return
        }
        #expect(accepted.point.systemSpeedMetersPerSecond == nil)
        #expect(LocationSampleValidator.freshSpeed(metersPerSecond: 3, sampleDate: now, now: now.addingTimeInterval(5)) == 3)
        #expect(LocationSampleValidator.freshSpeed(metersPerSecond: 3, sampleDate: now, now: now.addingTimeInterval(5.01)) == 0)
    }

    @Test
    func metricsAndFormattingUseRequiredUnits() {
        #expect(RideMetrics.speed(distanceMeters: 1_000, durationSeconds: 0) == 0)
        #expect(RideMetrics.speed(distanceMeters: 1_000, durationSeconds: 500) == 2)
        #expect(RideMetrics.speed(distanceMeters: 1_000, durationSeconds: 400) == 2.5)
        #expect(RideFormatting.distance(1_234) == "1.23 km")
        #expect(RideFormatting.speed(10) == "36.00 km/h")
        #expect(RideFormatting.liveDuration(3_599) == "59:59")
        #expect(RideFormatting.liveDuration(3_600) == "01:00:00")
        #expect(RideFormatting.fullDuration(65) == "00:01:05")
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
            segmentIndex: 0
        )
        let progress = RideProgress(
            totalElapsedSeconds: 100,
            movingElapsedSeconds: 80,
            distanceMeters: 500,
            maximumSpeedMetersPerSecond: 6,
            overallSpeedMetersPerSecond: 5,
            averageSpeedMetersPerSecond: 6.25,
            updatedAt: start.addingTimeInterval(100)
        )

        try await repository.createTemporaryRide(id: rideID, startDate: start, createdAt: start)
        #expect(try await repository.unfinishedRideIDs() == [rideID])
        try await repository.completeRide(
            RideCompletionSnapshot(
                rideID: rideID,
                endDate: start.addingTimeInterval(100),
                progress: progress
            ),
            pendingPoints: [point]
        )

        let records = try await repository.completedRides()
        #expect(records.count == 1)
        #expect(records.first?.status == .completed)
        #expect(records.first?.distanceMeters == 500)
        #expect(records.first?.totalElapsedSeconds == 100)
        #expect(records.first?.movingElapsedSeconds == 80)
        #expect(records.first?.overallSpeedMetersPerSecond == 5)
        #expect(records.first?.averageSpeedMetersPerSecond == 6.25)
        #expect(records.first?.points == [point])
        #expect(try await repository.unfinishedRideIDs().isEmpty)
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
        speed: Double = 2
    ) -> RawLocationSample {
        RawLocationSample(
            latitude: 39.9,
            longitude: longitude,
            timestamp: date,
            horizontalAccuracy: accuracy,
            systemSpeedMetersPerSecond: speed
        )
    }
}

private actor FakeRideRepository: RideRepository {
    private var created = 0
    private var completed = 0
    private var failCompletion = false

    func createTemporaryRide(id: UUID, startDate: Date, createdAt: Date) { created += 1 }
    func appendCheckpoint(rideID: UUID, points: [TrackPoint], progress: RideProgress) {}
    func completeRide(_ completion: RideCompletionSnapshot, pendingPoints: [TrackPoint]) throws {
        if failCompletion { throw FakeError.saveFailed }
        completed += 1
    }
    func completedRides() -> [RideRecord] { [] }
    func unfinishedRideIDs() -> [UUID] { [] }
    func discardUnfinishedRides() {}

    func setCompletionFailure(_ value: Bool) { failCompletion = value }
    func createdRideCount() -> Int { created }
    func completedRideCount() -> Int { completed }
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
