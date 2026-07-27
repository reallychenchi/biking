import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct RideView: View {
    @Bindable var controller: RideSessionController
    let isOffline: Bool

    @State private var cameraPosition: MapCameraPosition = .region(.chinaOverview)
    @State private var hasRequestedInitialLocation = false
    @State private var mapIsReady = false
    @Namespace private var mapScope

    var body: some View {
        ZStack(alignment: .bottom) {
            map

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
                        .stroke(AppTheme.accentForeground, lineWidth: 6)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
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
                withAnimation {
                    cameraPosition = .userLocation(
                        followsHeading: false,
                        fallback: .region(.chinaOverview)
                    )
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
                            .tint(AppTheme.accentForeground)
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
                            .tint(AppTheme.primaryActionForeground)
                    } else {
                        Text("开始")
                    }
                }
                .font(.system(size: 30, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: AppTheme.primaryButtonHeight)
                .foregroundStyle(AppTheme.primaryActionForeground)
                .background(AppTheme.primaryActionBackground, in: RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
            }
            .disabled(controller.phase.isBusy)
            .accessibilityLabel(controller.phase.isBusy ? "正在准备骑行" : "开始骑行")
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.vertical, 20)
        .frame(height: AppTheme.idlePanelHeight)
        .background(
            .ultraThinMaterial,
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
                    .foregroundStyle(controller.phase == .saveFailed ? AppTheme.destructive : AppTheme.secondaryText)
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
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(RideFormatting.liveDuration(controller.movingElapsedSeconds))
                        .font(.system(size: 42, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.accentForeground)
                        .minimumScaleFactor(0.72)
                    Text("全程时间  \(RideFormatting.fullDuration(controller.totalElapsedSeconds))")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.secondaryText)
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
            .ultraThinMaterial,
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
                .tint(AppTheme.destructiveForeground)
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
                .foregroundStyle(AppTheme.destructiveForeground)
                .background(color, in: RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
        }
    }
}

private enum RideMapConfiguration {
    static let overviewCenter = CLLocationCoordinate2D(latitude: 35.86, longitude: 104.19)
    static let overviewSpan = MKCoordinateSpan(latitudeDelta: 22, longitudeDelta: 24)
    static let overviewDisplayDuration: Duration = .milliseconds(1_500)
}

private extension MKCoordinateRegion {
    static let chinaOverview = MKCoordinateRegion(
        center: RideMapConfiguration.overviewCenter,
        span: RideMapConfiguration.overviewSpan
    )
}

private struct MetricColumn: View {
    let title: String
    let value: String
    let accessibilityValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.system(size: 52, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.primaryText)
                .minimumScaleFactor(0.64)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }
}
