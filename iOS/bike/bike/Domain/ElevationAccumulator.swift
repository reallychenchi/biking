import Foundation

enum ElevationCalculationConfiguration {
    static let maximumVerticalAccuracyMeters = 20.0
    static let minimumElevationTrendMeters = 3.0
    static let maximumContinuityGapSeconds = LocationValidationConfiguration.segmentGapInterval
}

struct ElevationMetrics: Hashable, Sendable {
    let cumulativeAscentMeters: Double?
    let cumulativeDescentMeters: Double?
    let minimumAltitudeMeters: Double?
    let maximumAltitudeMeters: Double?
}

struct ElevationAccumulator: Sendable {
    private struct Sample: Sendable {
        let altitudeMeters: Double
        let timestamp: Date
        let segmentIndex: Int
    }

    private enum Trend: Sendable {
        case undetermined(lowest: Double, highest: Double)
        case rising(anchorLow: Double, highest: Double)
        case falling(anchorHigh: Double, lowest: Double)
    }

    private var smoothingBuffer: [Sample] = []
    private var activeSegmentIndex: Int?
    private var lastValidTimestamp: Date?
    private var processedSampleCountInSegment = 0
    private var trend: Trend?
    private var committedAscentMeters = 0.0
    private var committedDescentMeters = 0.0
    private var minimumAltitudeMeters: Double?
    private var maximumAltitudeMeters: Double?
    private var hasComparablePair = false

    mutating func consume(_ point: TrackPoint) {
        guard let altitude = point.altitudeMeters,
              let verticalAccuracy = point.verticalAccuracyMeters,
              altitude.isFinite,
              verticalAccuracy.isFinite,
              verticalAccuracy >= 0,
              verticalAccuracy <= ElevationCalculationConfiguration.maximumVerticalAccuracyMeters else {
            return
        }

        let sample = Sample(
            altitudeMeters: altitude,
            timestamp: point.timestamp,
            segmentIndex: point.segmentIndex
        )
        if shouldStartNewSegment(with: sample) {
            finishSegment()
        }
        append(sample)
    }

    func metrics() -> ElevationMetrics {
        var finalized = self
        finalized.finishSegment()
        return finalized.makeMetrics()
    }

    private func shouldStartNewSegment(with sample: Sample) -> Bool {
        guard let activeSegmentIndex, let lastValidTimestamp else { return false }
        return sample.segmentIndex != activeSegmentIndex
            || sample.timestamp.timeIntervalSince(lastValidTimestamp)
                > ElevationCalculationConfiguration.maximumContinuityGapSeconds
    }

    private mutating func append(_ sample: Sample) {
        if activeSegmentIndex == nil {
            activeSegmentIndex = sample.segmentIndex
        }
        lastValidTimestamp = sample.timestamp
        smoothingBuffer.append(sample)

        if smoothingBuffer.count == 2 {
            processSmoothedAltitude(smoothingBuffer[0].altitudeMeters)
        } else if smoothingBuffer.count == 3 {
            processSmoothedAltitude(
                median(
                    smoothingBuffer[0].altitudeMeters,
                    smoothingBuffer[1].altitudeMeters,
                    smoothingBuffer[2].altitudeMeters
                )
            )
            smoothingBuffer.removeFirst()
        }
    }

    private mutating func finishSegment() {
        guard !smoothingBuffer.isEmpty else {
            resetSegmentState()
            return
        }

        if smoothingBuffer.count == 1 {
            processSmoothedAltitude(smoothingBuffer[0].altitudeMeters)
        } else {
            processSmoothedAltitude(smoothingBuffer[smoothingBuffer.count - 1].altitudeMeters)
        }
        commitPendingTrend()
        resetSegmentState()
    }

    private mutating func processSmoothedAltitude(_ altitude: Double) {
        processedSampleCountInSegment += 1
        if processedSampleCountInSegment >= 2 {
            hasComparablePair = true
        }
        minimumAltitudeMeters = minimumAltitudeMeters.map { min($0, altitude) } ?? altitude
        maximumAltitudeMeters = maximumAltitudeMeters.map { max($0, altitude) } ?? altitude

        let threshold = ElevationCalculationConfiguration.minimumElevationTrendMeters
        switch trend {
        case nil:
            trend = .undetermined(lowest: altitude, highest: altitude)

        case let .undetermined(lowest, highest):
            let updatedLowest = min(lowest, altitude)
            let updatedHighest = max(highest, altitude)
            if altitude - updatedLowest >= threshold {
                trend = .rising(anchorLow: updatedLowest, highest: updatedHighest)
            } else if updatedHighest - altitude >= threshold {
                trend = .falling(anchorHigh: updatedHighest, lowest: updatedLowest)
            } else {
                trend = .undetermined(lowest: updatedLowest, highest: updatedHighest)
            }

        case let .rising(anchorLow, highest):
            let updatedHighest = max(highest, altitude)
            if updatedHighest - altitude >= threshold {
                committedAscentMeters += updatedHighest - anchorLow
                trend = .falling(anchorHigh: updatedHighest, lowest: altitude)
            } else {
                trend = .rising(anchorLow: anchorLow, highest: updatedHighest)
            }

        case let .falling(anchorHigh, lowest):
            let updatedLowest = min(lowest, altitude)
            if altitude - updatedLowest >= threshold {
                committedDescentMeters += anchorHigh - updatedLowest
                trend = .rising(anchorLow: updatedLowest, highest: altitude)
            } else {
                trend = .falling(anchorHigh: anchorHigh, lowest: updatedLowest)
            }
        }
    }

    private mutating func commitPendingTrend() {
        switch trend {
        case let .rising(anchorLow, highest):
            committedAscentMeters += highest - anchorLow
        case let .falling(anchorHigh, lowest):
            committedDescentMeters += anchorHigh - lowest
        case .undetermined, nil:
            break
        }
    }

    private mutating func resetSegmentState() {
        smoothingBuffer.removeAll(keepingCapacity: true)
        activeSegmentIndex = nil
        lastValidTimestamp = nil
        processedSampleCountInSegment = 0
        trend = nil
    }

    private func makeMetrics() -> ElevationMetrics {
        ElevationMetrics(
            cumulativeAscentMeters: hasComparablePair ? committedAscentMeters : nil,
            cumulativeDescentMeters: hasComparablePair ? committedDescentMeters : nil,
            minimumAltitudeMeters: minimumAltitudeMeters,
            maximumAltitudeMeters: maximumAltitudeMeters
        )
    }

    private func median(_ first: Double, _ second: Double, _ third: Double) -> Double {
        [first, second, third].sorted()[1]
    }
}
