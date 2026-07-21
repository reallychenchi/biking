import CoreLocation
import Foundation
import OSLog

enum TrackingReadiness: Equatable {
    case ready
    case servicesDisabled
    case denied
    case restricted
    case preciseLocationRequired

    var message: String {
        switch self {
        case .ready:
            return ""
        case .servicesDisabled:
            return "定位服务已关闭，请在系统设置中开启定位服务。"
        case .denied:
            return "未获得定位权限，请在系统设置中允许“骑行”使用位置。"
        case .restricted:
            return "当前设备限制了定位权限，无法开始骑行。"
        case .preciseLocationRequired:
            return "记录骑行需要精确位置，请开启“精确位置”。"
        }
    }

    var canOpenSettings: Bool {
        switch self {
        case .servicesDisabled, .denied, .preciseLocationRequired:
            return true
        case .ready, .restricted:
            return false
        }
    }
}

enum TrackingIssue: Equatable, Sendable {
    case locationUnavailable
    case authorizationDenied
    case authorizationRestricted
    case insufficientlyInUse
    case accuracyLimited

    var message: String {
        switch self {
        case .locationUnavailable:
            return "定位暂时不可用，已停止累计距离和运动时间。"
        case .authorizationDenied:
            return "定位权限已关闭，已停止累计距离和运动时间。"
        case .authorizationRestricted:
            return "定位权限受到系统限制。"
        case .insufficientlyInUse:
            return "后台定位暂时不可用。"
        case .accuracyLimited:
            return "精确定位不可用，已停止累计距离和运动时间。"
        }
    }
}

struct TrackingUpdate: Sendable {
    let sample: RawLocationSample?
    let issue: TrackingIssue?
}

@MainActor
protocol RideTrackingProviding: AnyObject {
    func prepareForRide() async -> TrackingReadiness
    func startBackgroundActivity()
    func updates() -> AsyncStream<TrackingUpdate>
    func stop()
}

@MainActor
final class RideTrackingService: NSObject, CLLocationManagerDelegate, RideTrackingProviding {
    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<Void, Never>?
    private var backgroundSession: CLBackgroundActivitySession?
    private var updateTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
    }

    func prepareForRide() async -> TrackingReadiness {
        guard CLLocationManager.locationServicesEnabled() else {
            return .servicesDisabled
        }

        if manager.authorizationStatus == .notDetermined {
            AppLog.location.info("Requesting When In Use location authorization")
            await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }

        switch manager.authorizationStatus {
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .notDetermined:
            return .denied
        @unknown default:
            return .denied
        }

        if manager.accuracyAuthorization != .fullAccuracy {
            AppLog.location.info("Requesting temporary precise location authorization")
            await withCheckedContinuation { continuation in
                manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "RideTracking") { _ in
                    continuation.resume()
                }
            }
        }

        return manager.accuracyAuthorization == .fullAccuracy ? .ready : .preciseLocationRequired
    }

    func startBackgroundActivity() {
        guard backgroundSession == nil else { return }
        backgroundSession = CLBackgroundActivitySession()
        AppLog.location.info("Background location activity started")
    }

    func updates() -> AsyncStream<TrackingUpdate> {
        AsyncStream { continuation in
            updateTask?.cancel()
            let task = Task {
                do {
                    for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                        guard !Task.isCancelled else { break }
                        let issue: TrackingIssue?
                        if update.authorizationDenied {
                            issue = .authorizationDenied
                        } else if update.authorizationRestricted {
                            issue = .authorizationRestricted
                        } else if update.accuracyLimited {
                            issue = .accuracyLimited
                        } else if update.insufficientlyInUse {
                            issue = .insufficientlyInUse
                        } else if update.locationUnavailable {
                            issue = .locationUnavailable
                        } else {
                            issue = nil
                        }
                        continuation.yield(
                            TrackingUpdate(
                                sample: update.location.map(RawLocationSample.init),
                                issue: issue
                            )
                        )
                    }
                } catch is CancellationError {
                    // Normal shutdown when a ride ends.
                } catch {
                    AppLog.location.error("Location update stream failed: \(error.localizedDescription, privacy: .public)")
                    continuation.yield(TrackingUpdate(sample: nil, issue: .locationUnavailable))
                }
                continuation.finish()
            }
            updateTask = task
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func stop() {
        updateTask?.cancel()
        updateTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        AppLog.location.info("Background location activity stopped")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        AppLog.location.info("Location authorization changed")
        guard manager.authorizationStatus != .notDetermined else { return }
        authorizationContinuation?.resume()
        authorizationContinuation = nil
    }
}
