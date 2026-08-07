import SwiftUI
import UIKit
import OSLog

struct RideDetailView: View {
    private enum DetailTab {
        case details
        case route
    }

    private enum LoadState {
        case loading
        case loaded(RideDetailPresentation)
        case failed(String)
    }

    let summary: RideSummary
    let loadRide: () async throws -> RideRecord
    @State private var loadState = LoadState.loading
    @State private var retryToken = 0
    @State private var selectedTab = DetailTab.details
    @State private var sharePayload: RideSharePayload?
    @State private var shareError: ShareImageError?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                loadingBody
            case let .loaded(presentation):
                loadedBody(presentation: presentation)
            case let .failed(message):
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AppTheme.primaryText)
                } description: {
                    Text(message)
                        .foregroundStyle(AppTheme.secondaryText)
                } actions: {
                    Button("重试") { retryToken += 1 }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.primaryActionBackground)
                        .foregroundStyle(AppTheme.primaryActionForeground)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.pageBackground.ignoresSafeArea())
            }
        }
        .navigationTitle(RideFormatting.date(summary.startDate))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if case let .loaded(presentation) = loadState {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { shareDetail(presentation: presentation) } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("分享骑行详情")
                }
            }
        }
        .sheet(item: $sharePayload) { payload in
            RideImageShareSheet(image: payload.image)
        }
        .alert(item: $shareError) { error in
            Alert(
                title: Text("无法生成分享图片"),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text("知道了"))
            )
        }
        .task(id: TaskID(id: summary.id, token: retryToken)) {
            loadState = .loading
            do {
                let record = try await loadRide()
                try Task.checkCancellation()
                loadState = .loaded(RideDetailPresentation(ride: record))
            } catch is CancellationError {
                return
            } catch {
                loadState = .failed(error.localizedDescription)
                AppLog.history.error("Failed to load ride detail rideID=\(summary.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private var loadingBody: some View {
        ProgressView("正在加载…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                detailTabBar(isEnabled: false)
            }
    }

    @ViewBuilder
    private func loadedBody(presentation: RideDetailPresentation) -> some View {
        Group {
            switch selectedTab {
            case .details:
                RideDetailInfoView(presentation: presentation)
            case .route:
                RideRouteView(
                    geometry: presentation.routeGeometry,
                    routeStyle: .speedGradient
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            detailTabBar(isEnabled: true)
        }
    }

    private func detailTabBar(isEnabled: Bool) -> some View {
        HStack(spacing: 0) {
            detailTabButton("详情", systemImage: "list.bullet", tab: .details, isEnabled: isEnabled)
            detailTabButton("轨迹", systemImage: "map", tab: .route, isEnabled: isEnabled)
        }
        .padding(.top, 8)
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
    }

    private func detailTabButton(
        _ title: String,
        systemImage: String,
        tab: DetailTab,
        isEnabled: Bool
    ) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTheme.minimumTapSize)
            .foregroundStyle(selectedTab == tab ? AppTheme.accentForeground : AppTheme.secondaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        .accessibilityHint(isEnabled ? Text("") : Text("加载完成后可切换"))
    }

    private func shareDetail(presentation: RideDetailPresentation) {
        let renderer = ImageRenderer(
            content: RideDetailShareContent(presentation: presentation)
                .environment(\.colorScheme, colorScheme)
        )
        renderer.proposedSize = ProposedViewSize(width: UIScreen.main.bounds.width, height: nil)
        renderer.scale = displayScale

        guard let image = renderer.uiImage else {
            AppLog.history.error("Failed to render ride detail share image for ride \(presentation.ride.id, privacy: .public)")
            shareError = .renderingFailed
            return
        }

        sharePayload = RideSharePayload(image: image)
        AppLog.history.info("Rendered ride detail share image for ride \(presentation.ride.id, privacy: .public)")
    }

    private struct TaskID: Equatable {
        let id: UUID
        let token: Int
    }
}

private struct RideDetailPresentation {
    let ride: RideRecord
    let routeGeometry: RideRouteGeometry
    let speedAnalysis: RideSpeedAnalysis
    let maximumSpeedMetersPerSecond: Double

    init(ride: RideRecord) {
        self.ride = ride
        routeGeometry = RideRouteGeometry(points: ride.points)
        speedAnalysis = RideSpeedAnalysis(points: ride.points)
        maximumSpeedMetersPerSecond = RideSpeedAnomalyFilter.estimatedMaximumSpeed(points: ride.points)
    }
}

private struct RideDetailInfoView: View {
    let presentation: RideDetailPresentation

    var body: some View {
        ScrollView {
            RideDetailContent(presentation: presentation)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .foregroundStyle(AppTheme.primaryText)
    }
}

private struct RideDetailShareContent: View {
    let presentation: RideDetailPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(RideFormatting.date(presentation.ride.startDate))
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, RideDetailLayout.pagePadding)
                .padding(.top, RideDetailLayout.sectionSpacing)

            RideDetailContent(presentation: presentation)
        }
        .background(AppTheme.pageBackground)
        .foregroundStyle(AppTheme.primaryText)
    }
}

private struct RideDetailContent: View {
    private enum Unit {
        static let speed = "km/h"
        static let distance = "km"
        static let duration = "小时:分钟"
        static let elevation = "m"
    }

    let presentation: RideDetailPresentation
    private var ride: RideRecord {
        presentation.ride
    }

    var body: some View {
        VStack(spacing: RideDetailLayout.sectionSpacing) {
            VStack(spacing: RideDetailLayout.timeRowSpacing) {
                plainDetail("起止时间", rideTimeRange)
                plainDetail(
                    "海拔范围",
                    RideFormatting.elevationRange(
                        minimumMeters: ride.minimumAltitudeMeters,
                        maximumMeters: ride.maximumAltitudeMeters
                    )
                )
            }

            VStack(spacing: RideDetailLayout.cardSpacing) {
                ForEach(metricRows.indices, id: \.self) { rowIndex in
                    HStack(spacing: RideDetailLayout.cardSpacing) {
                        ForEach(metricRows[rowIndex]) { metric in
                            RideMetricCard(metric: metric)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                }
            }

            RideSpeedChartsView(
                analysis: presentation.speedAnalysis,
                endDistanceMeters: ride.distanceMeters
            )
        }
        .padding(.horizontal, RideDetailLayout.pagePadding)
        .padding(.vertical, RideDetailLayout.sectionSpacing)
    }

    private var metricRows: [[RideDetailMetric]] {
        stride(from: 0, to: metrics.count, by: 2).map { startIndex in
            Array(metrics[startIndex..<min(startIndex + 2, metrics.count)])
        }
    }

    private var rideTimeRange: String {
        let startTime = RideFormatting.time(ride.startDate)
        let endTime = ride.endDate.map(RideFormatting.time) ?? "—"
        return "\(startTime) - \(endTime)"
    }

    private var metrics: [RideDetailMetric] {
        [
            RideDetailMetric(
                title: "总距离",
                value: RideFormatting.distanceCardValue(ride.distanceMeters),
                unit: Unit.distance
            ),
            RideDetailMetric(
                title: "最快速度",
                value: RideFormatting.speedCardValue(presentation.maximumSpeedMetersPerSecond),
                unit: Unit.speed
            ),
            RideDetailMetric(
                title: "全程速度",
                value: RideFormatting.speedCardValue(ride.overallSpeedMetersPerSecond),
                unit: Unit.speed
            ),
            RideDetailMetric(
                title: "平均速度",
                value: RideFormatting.speedCardValue(ride.averageSpeedMetersPerSecond),
                unit: Unit.speed
            ),
            RideDetailMetric(
                title: "全程时间",
                value: RideFormatting.hourMinuteDuration(ride.totalElapsedSeconds),
                unit: Unit.duration
            ),
            RideDetailMetric(
                title: "运动时间",
                value: RideFormatting.hourMinuteDuration(ride.movingElapsedSeconds),
                unit: Unit.duration
            ),
            elevationMetric(title: "累积上升", meters: ride.cumulativeAscentMeters),
            elevationMetric(title: "累积下降", meters: ride.cumulativeDescentMeters)
        ]
    }

    private func plainDetail(_ title: String, _ text: String) -> some View {
        HStack {
            Text(title).foregroundStyle(AppTheme.secondaryText)
            Spacer()
            Text(text).monospacedDigit()
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private func elevationMetric(title: String, meters: Double?) -> RideDetailMetric {
        guard let value = RideFormatting.elevationCardValue(meters) else {
            return RideDetailMetric(title: title, value: RideFormatting.elevation(meters))
        }
        return RideDetailMetric(title: title, value: value, unit: Unit.elevation)
    }
}

private enum RideDetailLayout {
    static let pagePadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 28
    static let timeRowSpacing: CGFloat = 14
    static let cardSpacing: CGFloat = 18
}

private enum ShareImageError: LocalizedError, Identifiable {
    case renderingFailed

    var id: String { "renderingFailed" }

    var errorDescription: String? {
        "请稍后重试。"
    }
}

private struct RideSharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct RideImageShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct RideDetailMetric: Identifiable {
    let title: String
    let value: String
    let unit: String?

    var id: String { title }

    init(title: String, value: String, unit: String? = nil) {
        self.title = title
        self.value = value
        self.unit = unit
    }

    var formattedValue: String {
        let accessibleValue = value.trimmingCharacters(in: .whitespaces)
        guard let unit else { return accessibleValue }
        return "\(accessibleValue) \(unit)"
    }
}

private struct RideMetricCard: View {
    private enum Layout {
        static let padding: CGFloat = 20
        static let contentSpacing: CGFloat = 18
        static let cornerRadius: CGFloat = 20
        static let valueFontSize: CGFloat = 60
        static let minimumValueScale: CGFloat = 0.35
    }

    let metric: RideDetailMetric

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.contentSpacing) {
            Text(metric.title)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)

            Text(metric.value)
                .font(.system(size: Layout.valueFontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(Layout.minimumValueScale)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if let unit = metric.unit {
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(Layout.padding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            AppTheme.panelBackground,
            in: RoundedRectangle(cornerRadius: Layout.cornerRadius)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(metric.formattedValue)
    }
}
