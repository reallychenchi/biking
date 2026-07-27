import Charts
import SwiftUI

struct RideSpeedChartsView: View {
    private enum Layout {
        static let chartHeight: CGFloat = 240
        static let sectionSpacing: CGFloat = 28
        static let smallZoneThreshold = 0.10
        static let externalLabelSpacing: CGFloat = 28
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
                    Canvas { context, size in
                        drawSpeedZoneDonut(context: &context, size: size)
                    }
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

    private func drawSpeedZoneDonut(context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outerRadius = min(size.height * 0.31, size.width * 0.27)
        let innerRadius = outerRadius * 0.60
        let sectors = makeSectorLayouts()

        for sector in sectors {
            let angularGap = min(Double.pi / 180, sector.span * 0.15)
            var path = Path()
            path.addArc(
                center: center,
                radius: outerRadius,
                startAngle: .radians(sector.startAngle + angularGap),
                endAngle: .radians(sector.endAngle - angularGap),
                clockwise: false
            )
            path.addArc(
                center: center,
                radius: innerRadius,
                startAngle: .radians(sector.endAngle - angularGap),
                endAngle: .radians(sector.startAngle + angularGap),
                clockwise: true
            )
            path.closeSubpath()
            context.fill(path, with: .color(color(for: sector.share.zone.id)))
        }

        drawInternalZoneLabels(
            sectors.filter { $0.share.proportion >= Layout.smallZoneThreshold },
            context: &context,
            center: center,
            radius: (outerRadius + innerRadius) / 2
        )
        drawExternalZoneLabels(
            sectors.filter { $0.share.proportion < Layout.smallZoneThreshold },
            context: &context,
            size: size,
            center: center,
            outerRadius: outerRadius
        )
    }

    private func makeSectorLayouts() -> [SpeedZoneSectorLayout] {
        var startAngle = -Double.pi / 2
        return visibleZoneShares.map { share in
            let span = share.proportion * 2 * Double.pi
            let layout = SpeedZoneSectorLayout(
                share: share,
                startAngle: startAngle,
                endAngle: startAngle + span
            )
            startAngle += span
            return layout
        }
    }

    private func drawInternalZoneLabels(
        _ sectors: [SpeedZoneSectorLayout],
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat
    ) {
        for sector in sectors {
            let position = point(center: center, radius: radius, angle: sector.midAngle)
            let text = Text(zoneLabel(for: sector.share))
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.black)
            context.draw(text, at: position, anchor: .center)
        }
    }

    private func drawExternalZoneLabels(
        _ sectors: [SpeedZoneSectorLayout],
        context: inout GraphicsContext,
        size: CGSize,
        center: CGPoint,
        outerRadius: CGFloat
    ) {
        let naturalLayouts = sectors.map { sector in
            let target = point(center: center, radius: outerRadius + 12, angle: sector.midAngle)
            return SpeedZoneExternalLabelLayout(
                sector: sector,
                isRightSide: cos(sector.midAngle) >= 0,
                naturalY: target.y,
                labelY: target.y
            )
        }
        let leftLayouts = distributedExternalLabels(
            naturalLayouts.filter { !$0.isRightSide },
            height: size.height
        )
        let rightLayouts = distributedExternalLabels(
            naturalLayouts.filter(\.isRightSide),
            height: size.height
        )

        for layout in leftLayouts + rightLayouts {
            let direction: CGFloat = layout.isRightSide ? 1 : -1
            let anchorPoint = point(
                center: center,
                radius: outerRadius,
                angle: layout.sector.midAngle
            )
            let radialPoint = point(
                center: center,
                radius: outerRadius + 10,
                angle: layout.sector.midAngle
            )
            let text = Text(zoneLabel(for: layout.sector.share))
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.black)
            let resolvedText = context.resolve(text)
            let textSize = resolvedText.measure(
                in: CGSize(width: size.width, height: Layout.externalLabelSpacing)
            )
            let horizontalMargin: CGFloat = 2
            let halfTextWidth = textSize.width / 2
            let labelCenterX: CGFloat
            if layout.isRightSide {
                labelCenterX = size.width - horizontalMargin - halfTextWidth
            } else {
                labelCenterX = horizontalMargin + halfTextWidth
            }
            let lineEnd = CGPoint(
                x: labelCenterX - direction * (halfTextWidth + 4),
                y: layout.labelY
            )
            var leaderPath = Path()
            leaderPath.move(to: anchorPoint)
            leaderPath.addLine(to: radialPoint)
            leaderPath.addLine(to: lineEnd)
            context.stroke(
                leaderPath,
                with: .color(Color(uiColor: .systemGray)),
                lineWidth: 1.5
            )

            context.draw(
                resolvedText,
                at: CGPoint(x: labelCenterX, y: layout.labelY),
                anchor: .center
            )
        }
    }

    private func distributedExternalLabels(
        _ layouts: [SpeedZoneExternalLabelLayout],
        height: CGFloat
    ) -> [SpeedZoneExternalLabelLayout] {
        guard !layouts.isEmpty else { return [] }
        var result = layouts.sorted { $0.naturalY < $1.naturalY }
        let positions = NonOverlappingVerticalLabelLayout.positions(
            naturalYPositions: result.map(\.naturalY),
            height: height,
            spacing: Layout.externalLabelSpacing
        )
        for index in result.indices {
            result[index].labelY = positions[index]
        }
        return result
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(
            x: center.x + radius * CGFloat(cos(angle)),
            y: center.y + radius * CGFloat(sin(angle))
        )
    }

    private func zoneLabel(for share: RideSpeedZoneShare) -> String {
        share.zone.title
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

private struct SpeedZoneSectorLayout {
    let share: RideSpeedZoneShare
    let startAngle: Double
    let endAngle: Double

    var span: Double { endAngle - startAngle }
    var midAngle: Double { startAngle + span / 2 }
}

private struct SpeedZoneExternalLabelLayout {
    let sector: SpeedZoneSectorLayout
    let isRightSide: Bool
    let naturalY: CGFloat
    var labelY: CGFloat
}

struct NonOverlappingVerticalLabelLayout {
    static func positions(
        naturalYPositions: [CGFloat],
        height: CGFloat,
        spacing: CGFloat
    ) -> [CGFloat] {
        guard !naturalYPositions.isEmpty else { return [] }
        let minimumY = spacing / 2
        let maximumY = height - spacing / 2
        var positions = naturalYPositions

        positions[0] = max(minimumY, positions[0])
        for index in positions.indices.dropFirst() {
            positions[index] = max(positions[index], positions[index - 1] + spacing)
        }

        if let lastIndex = positions.indices.last, positions[lastIndex] > maximumY {
            positions[lastIndex] = maximumY
            for index in positions.indices.dropLast().reversed() {
                positions[index] = min(positions[index], positions[index + 1] - spacing)
            }
        }

        if positions[0] < minimumY {
            let offset = minimumY - positions[0]
            positions = positions.map { $0 + offset }
        }
        return positions
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
