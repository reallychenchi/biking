import SwiftUI
import UIKit
import OSLog

struct RideDetailView: View {
    private enum DetailTab {
        case details
        case route
    }

    let ride: RideRecord
    @State private var selectedTab = DetailTab.details
    @State private var sharePayload: RideSharePayload?
    @State private var shareError: ShareImageError?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            switch selectedTab {
            case .details:
                RideDetailInfoView(ride: ride)
            case .route:
                RideRouteView(ride: ride)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            detailTabBar
        }
        .navigationTitle(RideFormatting.date(ride.startDate))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: shareDetail) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("分享骑行详情")
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
    }

    private var detailTabBar: some View {
        HStack(spacing: 0) {
            detailTabButton("详情", systemImage: "list.bullet", tab: .details)
            detailTabButton("轨迹", systemImage: "map", tab: .route)
        }
        .padding(.top, 8)
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
    }

    private func detailTabButton(
        _ title: String,
        systemImage: String,
        tab: DetailTab
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
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }

    private func shareDetail() {
        let renderer = ImageRenderer(
            content: RideDetailShareContent(ride: ride)
                .environment(\.colorScheme, colorScheme)
        )
        renderer.proposedSize = ProposedViewSize(width: UIScreen.main.bounds.width, height: nil)
        renderer.scale = displayScale

        guard let image = renderer.uiImage else {
            AppLog.history.error("Failed to render ride detail share image for ride \(ride.id, privacy: .public)")
            shareError = .renderingFailed
            return
        }

        sharePayload = RideSharePayload(image: image)
        AppLog.history.info("Rendered ride detail share image for ride \(ride.id, privacy: .public)")
    }
}

private struct RideDetailInfoView: View {
    let ride: RideRecord

    var body: some View {
        ScrollView {
            RideDetailContent(ride: ride)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .foregroundStyle(AppTheme.primaryText)
    }
}

private struct RideDetailShareContent: View {
    let ride: RideRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(RideFormatting.date(ride.startDate))
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, RideDetailLayout.pagePadding)
                .padding(.top, RideDetailLayout.sectionSpacing)

            RideDetailContent(ride: ride)
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

    let ride: RideRecord

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
                points: ride.points,
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
                value: RideFormatting.speedCardValue(ride.maximumSpeedMetersPerSecond),
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
