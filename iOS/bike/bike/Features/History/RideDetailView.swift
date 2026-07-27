import SwiftUI

struct RideDetailView: View {
    let ride: RideRecord

    var body: some View {
        TabView {
            RideDetailInfoView(ride: ride)
                .tabItem { Label("详情", systemImage: "list.bullet") }
            RideRouteView(ride: ride)
                .tabItem { Label("轨迹", systemImage: "map") }
        }
        .navigationTitle(RideFormatting.date(ride.startDate))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(AppTheme.pageBackground, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct RideDetailInfoView: View {
    private enum Layout {
        static let pagePadding: CGFloat = 24
        static let sectionSpacing: CGFloat = 28
        static let timeRowSpacing: CGFloat = 14
        static let cardSpacing: CGFloat = 18
    }

    private enum Unit {
        static let speed = "km/h"
        static let distance = "km"
        static let elevation = "m"
    }

    let ride: RideRecord

    var body: some View {
        ScrollView {
            VStack(spacing: Layout.sectionSpacing) {
                LazyVGrid(columns: columns, spacing: Layout.cardSpacing) {
                    ForEach(metrics) { metric in
                        RideMetricCard(metric: metric)
                    }
                }

                VStack(spacing: Layout.timeRowSpacing) {
                    plainDetail(
                        "海拔范围",
                        RideFormatting.elevationRange(
                            minimumMeters: ride.minimumAltitudeMeters,
                            maximumMeters: ride.maximumAltitudeMeters
                        )
                    )
                    plainDetail("开始时间", RideFormatting.dateTime(ride.startDate))
                    plainDetail("结束时间", ride.endDate.map { RideFormatting.dateTime($0) } ?? "—")
                }
            }
            .padding(.horizontal, Layout.pagePadding)
            .padding(.vertical, Layout.sectionSpacing)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .foregroundStyle(.white)
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: Layout.cardSpacing),
            GridItem(.flexible())
        ]
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
                value: RideFormatting.hourMinuteDuration(ride.totalElapsedSeconds)
            ),
            RideDetailMetric(
                title: "运动时间",
                value: RideFormatting.hourMinuteDuration(ride.movingElapsedSeconds)
            ),
            elevationMetric(title: "累积上升", meters: ride.cumulativeAscentMeters),
            elevationMetric(title: "累积下降", meters: ride.cumulativeDescentMeters)
        ]
    }

    private func plainDetail(_ title: String, _ text: String) -> some View {
        HStack {
            Text(title).foregroundStyle(AppTheme.secondary)
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
                .foregroundStyle(AppTheme.secondary)

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
                    .foregroundStyle(AppTheme.secondary)
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
