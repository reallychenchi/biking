import CoreLocation
import MapKit
import OSLog
import SwiftUI
import UIKit

struct RideView: View {
    @Bindable var controller: RideSessionController
    let isOffline: Bool

    @State private var cameraPosition: MapCameraPosition = .region(.chinaOverview)
    @State private var mapLocationProvider = RideMapLocationProvider()
    @State private var hasRequestedInitialLocation = false
    @State private var mapIsReady = false
    @Namespace private var mapScope

    var body: some View {
        VStack(spacing: 0) {
            map
                .frame(maxHeight: .infinity)

            controlPanel
        }
        .background(AppTheme.pageBackground)
        .alert(
            controller.notice?.title ?? "",
            isPresented: Binding(
                get: { controller.notice != nil },
                set: { if !$0 { controller.dismissNotice() } }
            ),
            presenting: controller.notice
        ) { notice in
            if notice.offersSettings {
                Button("前往设置") { openSystemSettings() }
            }
            Button("知道了", role: .cancel) { controller.dismissNotice() }
        } message: { notice in
            Text(notice.message)
        }
    }

    private var map: some View {
        Map(position: $cameraPosition, scope: mapScope) {
            UserAnnotation()
            ForEach(Array(controller.trackSegments.enumerated()), id: \.offset) { _, segment in
                if segment.count >= 2 {
                    MapPolyline(coordinates: segment)
                        .stroke(AppTheme.accent, lineWidth: 6)
                }
            }
        }
        .mapScope(mapScope)
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton(scope: mapScope)
                .accessibilityLabel("回到当前位置")
            MapCompass(scope: mapScope)
                .accessibilityLabel("地图指南针")
        }
        .onMapCameraChange(frequency: .onEnd) {
            if !mapIsReady {
                withAnimation(.easeOut(duration: 0.4)) {
                    mapIsReady = true
                }
            }
            guard !hasRequestedInitialLocation else { return }
            hasRequestedInitialLocation = true
            Task {
                do {
                    try await Task.sleep(for: RideMapConfiguration.overviewDisplayDuration)
                } catch {
                    return
                }
                guard let coordinate = await mapLocationProvider.currentCoordinateIfAuthorized() else { return }
                withAnimation {
                    cameraPosition = .region(.nearby(coordinate))
                }
            }
        }
        .overlay {
            if isOffline {
                VStack {
                    Label("地图暂时无法加载", systemImage: "map.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.78), in: Capsule())
                    Spacer()
                }
                .padding(.top, 16)
                .allowsHitTesting(false)
            }
        }
        .overlay {
            if !mapIsReady {
                AppTheme.pageBackground
                    .overlay(alignment: .center) {
                        ProgressView()
                            .tint(AppTheme.accent)
                            .scaleEffect(1.5)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var controlPanel: some View {
        switch controller.phase {
        case .recording, .finishing, .saveFailed:
            RecordingControlPanel(controller: controller)
        case .idle, .requestingAuthorization, .starting:
            IdleControlPanel(controller: controller)
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct IdleControlPanel: View {
    @Bindable var controller: RideSessionController

    var body: some View {
        VStack(spacing: 10) {
            if let warning = controller.checkpointWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(AppTheme.destructive)
            }

            Button {
                Task { await controller.startRide() }
            } label: {
                Group {
                    if controller.phase.isBusy {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Text("开始")
                    }
                }
                .font(.system(size: 30, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: AppTheme.primaryButtonHeight)
                .foregroundStyle(.black)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
            }
            .disabled(controller.phase.isBusy)
            .accessibilityLabel(controller.phase.isBusy ? "正在准备骑行" : "开始骑行")
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.vertical, 20)
        .frame(height: AppTheme.idlePanelHeight)
        .background(
            AppTheme.panelBackground,
            in: UnevenRoundedRectangle(
                topLeadingRadius: AppTheme.panelCornerRadius,
                topTrailingRadius: AppTheme.panelCornerRadius
            )
        )
    }
}

private struct RecordingControlPanel: View {
    @Bindable var controller: RideSessionController

    var body: some View {
        VStack(spacing: 10) {
            if let status = controller.locationStatusMessage {
                Label(status, systemImage: "location.slash.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(controller.phase == .saveFailed ? AppTheme.destructive : AppTheme.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(status)
            }

            HStack(alignment: .top, spacing: 20) {
                MetricColumn(
                    title: "距离（公里）",
                    value: RideFormatting.distanceValue(controller.distanceMeters),
                    accessibilityValue: RideFormatting.distance(controller.distanceMeters)
                )
                MetricColumn(
                    title: "速度（公里/时）",
                    value: RideFormatting.speedValue(controller.currentSpeedMetersPerSecond),
                    accessibilityValue: RideFormatting.speed(controller.currentSpeedMetersPerSecond)
                )
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("运动时间")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondary)
                    Text(RideFormatting.liveDuration(controller.movingElapsedSeconds))
                        .font(.system(size: 42, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.accent)
                        .minimumScaleFactor(0.72)
                    Text("全程时间  \(RideFormatting.fullDuration(controller.totalElapsedSeconds))")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("运动时间 \(RideFormatting.fullDuration(controller.movingElapsedSeconds))，全程时间 \(RideFormatting.fullDuration(controller.totalElapsedSeconds))")

                actionButton
            }
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(height: AppTheme.recordingPanelHeight)
        .background(
            AppTheme.panelBackground,
            in: UnevenRoundedRectangle(
                topLeadingRadius: AppTheme.panelCornerRadius,
                topTrailingRadius: AppTheme.panelCornerRadius
            )
        )
    }

    @ViewBuilder
    private var actionButton: some View {
        switch controller.phase {
        case .recording:
            panelButton(title: "结束", color: AppTheme.destructive) {
                Task { await controller.endRide() }
            }
            .accessibilityLabel("结束并保存骑行")
        case .saveFailed:
            panelButton(title: "重试", color: AppTheme.destructive) {
                Task { await controller.retrySaving() }
            }
            .accessibilityLabel("重试保存骑行")
        case .finishing:
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, minHeight: AppTheme.primaryButtonHeight)
                .background(AppTheme.destructive.opacity(0.7), in: RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
                .accessibilityLabel("正在保存骑行")
        default:
            EmptyView()
        }
    }

    private func panelButton(
        title: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: AppTheme.primaryButtonHeight)
                .foregroundStyle(.white)
                .background(color, in: RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
        }
    }
}

@MainActor
private final class RideMapLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentCoordinateIfAuthorized() async -> CLLocationCoordinate2D? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .denied, .notDetermined, .restricted:
            return nil
        @unknown default:
            assertionFailure("Unhandled location authorization status")
            return nil
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else {
            finish(with: nil)
            return
        }
        AppLog.location.info("Initial map location resolved")
        finish(with: location.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLog.location.warning("Initial map location unavailable: \(error.localizedDescription, privacy: .public)")
        finish(with: nil)
    }

    private func finish(with coordinate: CLLocationCoordinate2D?) {
        continuation?.resume(returning: coordinate)
        continuation = nil
    }
}

private enum RideMapConfiguration {
    static let overviewCenter = CLLocationCoordinate2D(latitude: 35.86, longitude: 104.19)
    static let overviewSpan = MKCoordinateSpan(latitudeDelta: 22, longitudeDelta: 24)
    static let overviewDisplayDuration: Duration = .milliseconds(1_500)
    static let nearbyRegionMeters: CLLocationDistance = 1_200
}

private extension MKCoordinateRegion {
    static let chinaOverview = MKCoordinateRegion(
        center: RideMapConfiguration.overviewCenter,
        span: RideMapConfiguration.overviewSpan
    )

    static func nearby(_ coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: RideMapConfiguration.nearbyRegionMeters,
            longitudinalMeters: RideMapConfiguration.nearbyRegionMeters
        )
    }
}

private struct MetricColumn: View {
    let title: String
    let value: String
    let accessibilityValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondary)
            Text(value)
                .font(.system(size: 52, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.64)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }
}
