import CoreLocation
import Foundation
import Observation
import OSLog

enum RideSessionPhase: Equatable {
    case idle
    case requestingAuthorization
    case starting
    case recording
    case finishing
    case saveFailed

    var isBusy: Bool {
        switch self {
        case .requestingAuthorization, .starting, .finishing:
            return true
        case .idle, .recording, .saveFailed:
            return false
        }
    }
}

private enum RideSessionConfiguration {
    static let shortRideDurationThresholdSeconds: TimeInterval = 5
}

struct RideNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let offersSettings: Bool

    init(title: String = "无法开始骑行", message: String, offersSettings: Bool) {
        self.title = title
        self.message = message
        self.offersSettings = offersSettings
    }
}

@MainActor
@Observable
final class RideSessionController {
    private struct ActiveRide {
        let id: UUID
        let startDate: Date
        let startInstant: ContinuousClock.Instant
        var validator = LocationSampleValidator()
        var movementTime = MovementTimeAccumulator()
        var elevation = ElevationAccumulator()
        var pendingPoints: [TrackPoint] = []
        var segments: [[CLLocationCoordinate2D]] = []
        var distanceMeters = 0.0
        var maximumSpeedMetersPerSecond = 0.0
        var speedFilter = RideSpeedAnomalyFilter.StreamingState()
        var latestSpeedMetersPerSecond: Double?
        var latestSpeedDate: Date?
        var latestAcceptedLocationDate: Date?

        mutating func consumeMaximumSpeedCandidate(_ point: TrackPoint) {
            guard let speed = speedFilter.consume(point) else { return }
            maximumSpeedMetersPerSecond = max(maximumSpeedMetersPerSecond, speed)
        }

        mutating func finishMaximumSpeedCandidates() {
            for speed in speedFilter.finish() {
                maximumSpeedMetersPerSecond = max(maximumSpeedMetersPerSecond, speed)
            }
        }
    }

    private let repository: any RideRepository
    private let trackingService: any RideTrackingProviding
    private let clock = ContinuousClock()

    private var activeRide: ActiveRide?
    private var pendingCompletion: RideCompletionSnapshot?
    private var timerTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?
    private var checkpointTask: Task<Void, Never>?
    private var trackingIssue: TrackingIssue?

    var onRideSaved: (() async -> Void)?

    private(set) var phase: RideSessionPhase = .idle
    private(set) var totalElapsedSeconds: TimeInterval = 0
    private(set) var movingElapsedSeconds: TimeInterval = 0
    private(set) var currentSpeedMetersPerSecond = 0.0
    private(set) var notice: RideNotice?
    private(set) var checkpointWarning: String?

    var distanceMeters: Double { activeRide?.distanceMeters ?? 0 }
    var maximumSpeedMetersPerSecond: Double { activeRide?.maximumSpeedMetersPerSecond ?? 0 }
    var trackSegments: [[CLLocationCoordinate2D]] { activeRide?.segments ?? [] }
    var latestCoordinate: CLLocationCoordinate2D? { activeRide?.segments.last?.last }
    var latestCoordinateToken: Int { activeRide?.validator.nextSequence ?? 0 }

    var locationStatusMessage: String? {
        guard phase == .recording else { return checkpointWarning }
        if let trackingIssue {
            return trackingIssue.message
        }
        guard let activeRide else { return nil }
        if let latestDate = activeRide.latestAcceptedLocationDate {
            if Date().timeIntervalSince(latestDate) > LocationValidationConfiguration.speedFreshnessInterval {
                return "定位信号较弱，已停止累计距离和运动时间。"
            }
        } else if totalElapsedSeconds >= LocationValidationConfiguration.speedFreshnessInterval {
            return "正在等待有效定位，当前不会累计距离和运动时间。"
        }
        return checkpointWarning
    }

    init(repository: any RideRepository, trackingService: any RideTrackingProviding) {
        self.repository = repository
        self.trackingService = trackingService
    }

    func startRide() async {
        guard phase == .idle else {
            AppLog.ride.warning("Ignored duplicate ride start request")
            return
        }

        phase = .requestingAuthorization
        let readiness = await trackingService.prepareForRide()
        guard readiness == .ready else {
            phase = .idle
            notice = RideNotice(message: readiness.message, offersSettings: readiness.canOpenSettings)
            AppLog.location.warning("Ride start blocked by location readiness")
            return
        }

        phase = .starting
        let rideID = UUID()
        let startDate = Date()
        do {
            try await repository.createTemporaryRide(id: rideID, startDate: startDate, createdAt: startDate)
        } catch {
            phase = .idle
            notice = RideNotice(message: "无法创建本地骑行记录：\(error.localizedDescription)", offersSettings: false)
            AppLog.persistence.error("Failed to create temporary ride: \(error.localizedDescription, privacy: .public)")
            return
        }

        activeRide = ActiveRide(id: rideID, startDate: startDate, startInstant: clock.now)
        totalElapsedSeconds = 0
        movingElapsedSeconds = 0
        currentSpeedMetersPerSecond = 0
        trackingIssue = nil
        checkpointWarning = nil
        pendingCompletion = nil
        phase = .recording

        trackingService.startBackgroundActivity()
        startRuntimeTasks()
        AppLog.ride.info("Ride started")
    }

    func endRide() async {
        guard phase == .recording, activeRide != nil else { return }
        phase = .finishing
        stopRuntimeTasks()
        refreshTimeAndSpeed()
        currentSpeedMetersPerSecond = 0

        guard var activeRide else {
            assertionFailure("Recording state requires an active ride")
            phase = .idle
            return
        }
        activeRide.finishMaximumSpeedCandidates()
        self.activeRide = activeRide

        if totalElapsedSeconds <= RideSessionConfiguration.shortRideDurationThresholdSeconds {
            AppLog.ride.info("Ride discarded: duration \(Int(self.totalElapsedSeconds))s is at or below threshold \(Int(RideSessionConfiguration.shortRideDurationThresholdSeconds))s")
            do {
                try await repository.deleteRide(id: activeRide.id)
            } catch {
                assertionFailure("Failed to delete short ride: \(error)")
                AppLog.persistence.error("Failed to delete short ride: \(error.localizedDescription, privacy: .public)")
            }
            self.activeRide = nil
            pendingCompletion = nil
            totalElapsedSeconds = 0
            movingElapsedSeconds = 0
            checkpointWarning = nil
            trackingIssue = nil
            phase = .idle
            notice = RideNotice(title: "骑行时间太短", message: "本次骑行时间不足，不计入记录。", offersSettings: false)
            return
        }

        let now = Date()
        let progress = makeProgress(from: activeRide, updatedAt: now)
        if progress.minimumAltitudeMeters == nil {
            AppLog.location.warning("Ride completed without valid elevation samples")
        }
        pendingCompletion = RideCompletionSnapshot(rideID: activeRide.id, endDate: now, progress: progress)
        await saveCompletion()
    }

    func retrySaving() async {
        guard phase == .saveFailed, pendingCompletion != nil else { return }
        phase = .finishing
        await saveCompletion()
    }

    func dismissNotice() {
        notice = nil
    }

    func appDidEnterBackground() {
        guard phase == .recording else { return }
        Task { await flushCheckpoint() }
    }

    func appWillEnterForeground() {
        guard phase == .recording else { return }
        refreshTimeAndSpeed()
    }

    private func startRuntimeTasks() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self?.refreshTimeAndSpeed()
            }
        }

        checkpointTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await self?.flushCheckpoint()
            }
        }

        let updates = trackingService.updates()
        locationTask = Task { [weak self] in
            for await update in updates {
                guard !Task.isCancelled else { break }
                self?.consume(update)
            }
        }
    }

    private func stopRuntimeTasks() {
        timerTask?.cancel()
        checkpointTask?.cancel()
        locationTask?.cancel()
        timerTask = nil
        checkpointTask = nil
        locationTask = nil
        trackingService.stop()
        currentSpeedMetersPerSecond = 0
    }

    private func consume(_ update: TrackingUpdate) {
        guard phase == .recording, var activeRide else { return }
        trackingIssue = update.issue
        guard let sample = update.sample else {
            activeRide.movementTime.consume(
                speedMetersPerSecond: nil,
                at: elapsed(from: activeRide.startInstant)
            )
            self.activeRide = activeRide
            currentSpeedMetersPerSecond = 0
            if let issue = update.issue {
                AppLog.location.warning("Location quality degraded: \(issue.message, privacy: .public)")
            }
            return
        }

        switch activeRide.validator.validate(sample) {
        case let .rejected(reason):
            activeRide.movementTime.consume(
                speedMetersPerSecond: nil,
                at: elapsed(from: activeRide.startInstant)
            )
            currentSpeedMetersPerSecond = 0
            trackingIssue = .locationUnavailable
            AppLog.location.warning("Rejected location sample: \(String(describing: reason), privacy: .public)")

        case let .accepted(accepted):
            trackingIssue = update.issue
            activeRide.pendingPoints.append(accepted.point)
            activeRide.distanceMeters += accepted.distanceFromPreviousMeters
            activeRide.latestAcceptedLocationDate = accepted.point.timestamp
            activeRide.elevation.consume(accepted.point)

            if accepted.startedNewSegment {
                activeRide.segments.append([accepted.point.mapDisplayCoordinate])
            } else if activeRide.segments.isEmpty {
                activeRide.segments = [[accepted.point.mapDisplayCoordinate]]
            } else {
                activeRide.segments[activeRide.segments.count - 1].append(accepted.point.mapDisplayCoordinate)
            }

            if !accepted.discardedDriftSegment,
               let speed = accepted.point.systemSpeedMetersPerSecond {
                activeRide.latestSpeedMetersPerSecond = speed
                activeRide.latestSpeedDate = accepted.point.timestamp
            }
            activeRide.consumeMaximumSpeedCandidate(accepted.point)
            if accepted.discardedDriftSegment {
                AppLog.location.warning("Discarded a drifting location segment")
            }
            activeRide.movementTime.consume(
                speedMetersPerSecond: accepted.point.systemSpeedMetersPerSecond,
                at: elapsed(from: activeRide.startInstant)
            )
        }

        self.activeRide = activeRide
        refreshTimeAndSpeed()
    }

    private func refreshTimeAndSpeed() {
        guard let activeRide else { return }
        let totalElapsed = elapsed(from: activeRide.startInstant)
        totalElapsedSeconds = totalElapsed
        var movementTime = activeRide.movementTime
        movingElapsedSeconds = movementTime.elapsed(at: totalElapsed)
        self.activeRide?.movementTime = movementTime
        currentSpeedMetersPerSecond = LocationSampleValidator.freshSpeed(
            metersPerSecond: activeRide.latestSpeedMetersPerSecond,
            sampleDate: activeRide.latestSpeedDate,
            now: Date()
        )
    }

    private func flushCheckpoint() async {
        guard phase == .recording, let activeRide, !activeRide.pendingPoints.isEmpty else { return }
        let pointsToSave = activeRide.pendingPoints
        let progress = makeProgress(from: activeRide, updatedAt: Date())

        do {
            try await repository.appendCheckpoint(rideID: activeRide.id, points: pointsToSave, progress: progress)
            let savedIDs = Set(pointsToSave.map(\.id))
            self.activeRide?.pendingPoints.removeAll { savedIDs.contains($0.id) }
            checkpointWarning = nil
        } catch {
            checkpointWarning = "临时保存失败，稍后将自动重试。"
            AppLog.persistence.error("Checkpoint save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func saveCompletion() async {
        guard let completion = pendingCompletion, let activeRide else {
            assertionFailure("Finishing state requires a completion snapshot")
            phase = .saveFailed
            return
        }

        do {
            try await repository.completeRide(completion, pendingPoints: activeRide.pendingPoints)
            AppLog.persistence.info("Completed ride saved")
            self.activeRide = nil
            pendingCompletion = nil
            totalElapsedSeconds = 0
            movingElapsedSeconds = 0
            currentSpeedMetersPerSecond = 0
            checkpointWarning = nil
            trackingIssue = nil
            phase = .idle
            await onRideSaved?()
        } catch {
            phase = .saveFailed
            checkpointWarning = "保存失败，请重试。"
            AppLog.persistence.error("Completed ride save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeProgress(from ride: ActiveRide, updatedAt: Date) -> RideProgress {
        let totalElapsed = elapsed(from: ride.startInstant)
        var movementTime = ride.movementTime
        let movingElapsed = movementTime.elapsed(at: totalElapsed)
        let elevation = ride.elevation.metrics()
        return RideProgress(
            totalElapsedSeconds: totalElapsed,
            movingElapsedSeconds: movingElapsed,
            distanceMeters: ride.distanceMeters,
            maximumSpeedMetersPerSecond: ride.maximumSpeedMetersPerSecond,
            overallSpeedMetersPerSecond: RideMetrics.speed(
                distanceMeters: ride.distanceMeters,
                durationSeconds: totalElapsed
            ),
            averageSpeedMetersPerSecond: RideMetrics.speed(
                distanceMeters: ride.distanceMeters,
                durationSeconds: movingElapsed
            ),
            cumulativeAscentMeters: elevation.cumulativeAscentMeters,
            cumulativeDescentMeters: elevation.cumulativeDescentMeters,
            minimumAltitudeMeters: elevation.minimumAltitudeMeters,
            maximumAltitudeMeters: elevation.maximumAltitudeMeters,
            updatedAt: updatedAt
        )
    }

    private func elapsed(from start: ContinuousClock.Instant) -> TimeInterval {
        let components = start.duration(to: clock.now).components
        return max(0, Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}
