import Charts
import SwiftUI

struct RideSpeedChartsView: View {
    private enum Layout {
        static let chartHeight: CGFloat = 240
        static let sectionSpacing: CGFloat = 28
    }

    private static let zoneColors = [
        Color(red: 0.93, green: 0.11, blue: 0.20),
        Color(red: 0.94, green: 0.30, blue: 0.12),
        Color(red: 0.90, green: 0.52, blue: 0.10),
        Color(red: 0.70, green: 0.68, blue: 0.10),
        Color(red: 0.38, green: 0.68, blue: 0.20),
        Color(red: 0.12, green: 0.62, blue: 0.32)
    ]

    private let analysis: RideSpeedAnalysis
    private let endDistanceMeters: Double

    init(points: [TrackPoint], endDistanceMeters: Double) {
        analysis = RideSpeedAnalysis(points: points)
        self.endDistanceMeters = max(0, endDistanceMeters)
    }

    var body: some View {
        VStack(spacing: Layout.sectionSpacing) {
            speedDistanceCard
            speedZoneCard
        }
    }

    private var speedDistanceCard: some View {
        RideAnalysisCard(
            title: "速度与骑行距离",
            subtitle: "横轴为累计骑行距离，纵轴为有效系统速度"
        ) {
            if analysis.chartPoints.count >= 2 {
                Chart {
                    ForEach(analysis.chartPoints) { point in
                        LineMark(
                            x: .value("骑行距离", point.cumulativeDistanceMeters / 1_000),
                            y: .value("速度", point.speedMetersPerSecond * 3.6),
                            series: .value("连续速度区间", point.seriesIndex)
                        )
                        .foregroundStyle(AppTheme.accentForeground)
                        .interpolationMethod(.linear)
                    }

                    RuleMark(x: .value("结束距离", endDistanceKilometers))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .trailing, spacing: 4) {
                            Text("结束 \(RideFormatting.distance(endDistanceMeters))")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.secondaryText)
                                .padding(.horizontal, 4)
                                .background(AppTheme.panelBackground)
                        }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxisLabel("距离 (km)", position: .bottom, alignment: .leading)
                .chartYAxisLabel("速度 (km/h)")
                .chartXScale(domain: 0...distanceAxisUpperBound)
                .chartYScale(domain: 0...speedAxisUpperBound)
                .frame(height: Layout.chartHeight)
                .accessibilityLabel("速度与骑行距离折线图")
                .accessibilityValue(speedChartAccessibilityValue)
            } else {
                unavailableContent("有效速度数据不足，无法生成速度曲线。")
            }
        }
    }

    private var speedZoneCard: some View {
        RideAnalysisCard(
            title: "速度区间",
            subtitle: "各速度区间对应的有效骑行距离占比"
        ) {
            if analysis.classifiedDistanceMeters > 0 {
                ZStack {
                    Chart(visibleZoneShares) { share in
                        SectorMark(
                            angle: .value("骑行距离", share.distanceMeters),
                            innerRadius: .ratio(0.6),
                            angularInset: 1.5
                        )
                        .foregroundStyle(color(for: share.zone.id))
                        .cornerRadius(3)
                        .annotation(position: .overlay) {
                            Text(compactZoneTitle(share.zone.title))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.65)
                                .shadow(color: .black.opacity(0.45), radius: 1)
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(height: Layout.chartHeight)
                    .accessibilityLabel("速度区间距离占比圆环图")
                    .accessibilityValue(zoneChartAccessibilityValue)

                    VStack(spacing: 2) {
                        Text(RideFormatting.distance(analysis.classifiedDistanceMeters))
                            .font(.headline)
                            .monospacedDigit()
                        Text("有效距离")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .accessibilityHidden(true)
                }

                if analysis.unclassifiedDistanceMeters > 0 {
                    Text("另有 \(RideFormatting.distance(analysis.unclassifiedDistanceMeters)) 因速度无效，未计入区间占比。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                unavailableContent("没有可用于区间统计的有效速度距离。")
            }
        }
    }

    private var visibleZoneShares: [RideSpeedZoneShare] {
        analysis.zoneShares.filter { $0.distanceMeters > 0 }
    }

    private var speedAxisUpperBound: Double {
        let maximumSpeed = analysis.chartPoints.map(\.speedMetersPerSecond).max() ?? 0
        let maximumKilometersPerHour = maximumSpeed * 3.6
        return max(5, ceil(maximumKilometersPerHour / 5) * 5)
    }

    private var endDistanceKilometers: Double {
        endDistanceMeters / 1_000
    }

    private var distanceAxisUpperBound: Double {
        let reconstructedDistanceKilometers = analysis.totalDistanceMeters / 1_000
        return max(0.1, endDistanceKilometers, reconstructedDistanceKilometers)
    }

    private var speedChartAccessibilityValue: String {
        let maximumSpeed = analysis.chartPoints.map(\.speedMetersPerSecond).max() ?? 0
        return "共 \(analysis.chartPoints.count) 个有效速度点，最高速度 \(RideFormatting.speed(maximumSpeed))，结束距离 \(RideFormatting.distance(endDistanceMeters))。"
    }

    private var zoneChartAccessibilityValue: String {
        visibleZoneShares.map { share in
            "\(share.zone.title) \(share.proportion.formatted(.percent.precision(.fractionLength(0))))"
        }.joined(separator: "，")
    }

    private func compactZoneTitle(_ title: String) -> String {
        title.replacingOccurrences(of: " km/h", with: "\nkm/h")
    }

    private func color(for zoneID: Int) -> Color {
        guard Self.zoneColors.indices.contains(zoneID) else {
            assertionFailure("Missing speed zone color")
            return AppTheme.secondaryText
        }
        return Self.zoneColors[zoneID]
    }

    private func unavailableContent(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 120)
            .multilineTextAlignment(.center)
    }
}

private struct RideAnalysisCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppTheme.panelBackground,
            in: RoundedRectangle(cornerRadius: 20)
        )
    }
}
