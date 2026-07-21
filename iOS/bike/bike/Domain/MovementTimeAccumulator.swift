import Foundation

enum MovementTimeConfiguration {
    static let startSpeedMetersPerSecond = 0.8
    static let stopSpeedMetersPerSecond = 0.3
    static let speedFreshnessInterval = LocationValidationConfiguration.speedFreshnessInterval
}

struct MovementTimeAccumulator: Sendable {
    private(set) var accumulatedSeconds: TimeInterval = 0
    private(set) var isMoving = false

    private var movingStartedAt: TimeInterval?
    private var latestSpeedAt: TimeInterval?

    mutating func consume(speedMetersPerSecond: Double?, at elapsedSeconds: TimeInterval) {
        let now = max(0, elapsedSeconds)
        expireStaleMovement(at: now)

        guard let speedMetersPerSecond, speedMetersPerSecond.isFinite, speedMetersPerSecond >= 0 else {
            stopMoving(at: now)
            latestSpeedAt = nil
            return
        }

        latestSpeedAt = now
        if isMoving {
            if speedMetersPerSecond <= MovementTimeConfiguration.stopSpeedMetersPerSecond {
                stopMoving(at: now)
            }
        } else if speedMetersPerSecond >= MovementTimeConfiguration.startSpeedMetersPerSecond {
            isMoving = true
            movingStartedAt = now
        }
    }

    mutating func elapsed(at elapsedSeconds: TimeInterval) -> TimeInterval {
        let now = max(0, elapsedSeconds)
        expireStaleMovement(at: now)
        guard isMoving, let movingStartedAt else { return accumulatedSeconds }
        return accumulatedSeconds + max(0, now - movingStartedAt)
    }

    private mutating func expireStaleMovement(at elapsedSeconds: TimeInterval) {
        guard isMoving, let latestSpeedAt else { return }
        let expiresAt = latestSpeedAt + MovementTimeConfiguration.speedFreshnessInterval
        if elapsedSeconds > expiresAt {
            stopMoving(at: expiresAt)
            self.latestSpeedAt = nil
        }
    }

    private mutating func stopMoving(at elapsedSeconds: TimeInterval) {
        guard isMoving, let movingStartedAt else { return }
        accumulatedSeconds += max(0, elapsedSeconds - movingStartedAt)
        isMoving = false
        self.movingStartedAt = nil
    }
}
