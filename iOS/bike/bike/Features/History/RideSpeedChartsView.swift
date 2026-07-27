import Charts
import SwiftUI

struct RideSpeedChartsView: View {
    private enum Layout {
        static let chartHeight: CGFloat = 240
        static let speedZoneOuterRadiusRatio: CGFloat = 0.31
        static let speedZoneWidthRadiusRatio: CGFloat = 0.27
        static let sectionSpacing: CGFloat = 28
        static let smallZoneThreshold = 0.10
        static let externalLabelSpacing: CGFloat = 14
        static let externalLabelRadiusOffset: CGFloat = 12
        static let externalLeaderMinimumLength: CGFloat = 10
        static let externalLabelHorizontalMargin: CGFloat = 2
        static let externalLeaderTextSpacing: CGFloat = 4
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
                let geometry = speedZoneChartGeometry
                ZStack {
                    Canvas { context, size in
                        drawSpeedZoneDonut(
                            context: &context,
                            size: size,
                            centerY: geometry.centerY
                        )
                    }
                    .frame(height: geometry.height)
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
                    .offset(y: geometry.centerY - geometry.height / 2)
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

    private var speedZoneChartGeometry: SpeedZoneChartGeometry {
        let baseCenterY = Layout.chartHeight / 2
        let referenceOuterRadius = Layout.chartHeight * Layout.speedZoneOuterRadiusRatio
        let externalSectors = makeSectorLayouts().filter {
            $0.share.proportion < Layout.smallZoneThreshold
        }
        let labelRadii = [
            referenceOuterRadius + Layout.externalLabelRadiusOffset,
            Layout.externalLabelRadiusOffset
        ]
        let positions = labelRadii.flatMap { labelRadius in
            let naturalLayouts = externalSectors.map { sector in
                SpeedZoneExternalLabelLayout(
                    sector: sector,
                    isRightSide: cos(sector.midAngle) >= 0,
                    naturalY: baseCenterY
                        + labelRadius * CGFloat(sin(sector.midAngle)),
                    labelY: baseCenterY
                )
            }
            return [false, true].flatMap { isRightSide in
                distributedExternalLabels(
                    naturalLayouts.filter { $0.isRightSide == isRightSide },
                    centerY: baseCenterY
                ).map(\.labelY)
            }
        }
        return SpeedZoneChartGeometry.make(
            baseHeight: Layout.chartHeight,
            labelYPositions: positions,
            verticalMargin: Layout.externalLabelSpacing / 2
        )
    }

    private func drawSpeedZoneDonut(
        context: inout GraphicsContext,
        size: CGSize,
        centerY: CGFloat
    ) {
        let center = CGPoint(x: size.width / 2, y: centerY)
        let outerRadius = min(
            Layout.chartHeight * Layout.speedZoneOuterRadiusRatio,
            size.width * Layout.speedZoneWidthRadiusRatio
        )
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
            let target = point(
                center: center,
                radius: outerRadius + Layout.externalLabelRadiusOffset,
                angle: sector.midAngle
            )
            return SpeedZoneExternalLabelLayout(
                sector: sector,
                isRightSide: cos(sector.midAngle) >= 0,
                naturalY: target.y,
                labelY: target.y
            )
        }
        let leftLayouts = distributedExternalLabels(
            naturalLayouts.filter { !$0.isRightSide },
            centerY: center.y
        )
        let rightLayouts = distributedExternalLabels(
            naturalLayouts.filter(\.isRightSide),
            centerY: center.y
        )

        drawExternalZoneLabels(
            leftLayouts,
            context: &context,
            size: size,
            center: center,
            outerRadius: outerRadius
        )
        drawExternalZoneLabels(
            rightLayouts,
            context: &context,
            size: size,
            center: center,
            outerRadius: outerRadius
        )
    }

    private func drawExternalZoneLabels(
        _ layouts: [SpeedZoneExternalLabelLayout],
        context: inout GraphicsContext,
        size: CGSize,
        center: CGPoint,
        outerRadius: CGFloat
    ) {
        guard let firstLayout = layouts.first else { return }
        let isRightSide = firstLayout.isRightSide
        let direction: CGFloat = isRightSide ? 1 : -1
        let maximumTextWidth = layouts.map { layout in
            let resolvedText = context.resolve(externalLabelText(for: layout))
            return resolvedText.measure(
                in: CGSize(width: size.width, height: Layout.externalLabelSpacing)
            ).width
        }.max() ?? 0
        let routingX: CGFloat
        if isRightSide {
            routingX = size.width
                - Layout.externalLabelHorizontalMargin
                - maximumTextWidth
                - Layout.externalLeaderTextSpacing
        } else {
            routingX = Layout.externalLabelHorizontalMargin
                + maximumTextWidth
                + Layout.externalLeaderTextSpacing
        }
        let usesRoutingLane = layouts.contains { layout in
            let elbow = externalLeaderElbow(
                center: center,
                outerRadius: outerRadius,
                angle: layout.sector.midAngle,
                labelY: layout.labelY
            )
            return isRightSide ? elbow.x > routingX : elbow.x < routingX
        }

        for layout in layouts {
            let anchorPoint = point(
                center: center,
                radius: outerRadius,
                angle: layout.sector.midAngle
            )
            let resolvedText = context.resolve(externalLabelText(for: layout))
            let textSize = resolvedText.measure(
                in: CGSize(width: size.width, height: Layout.externalLabelSpacing)
            )
            let halfTextWidth = textSize.width / 2
            let labelCenterX: CGFloat
            if layout.isRightSide {
                labelCenterX = size.width
                    - Layout.externalLabelHorizontalMargin
                    - halfTextWidth
            } else {
                labelCenterX = Layout.externalLabelHorizontalMargin + halfTextWidth
            }
            let lineEnd = CGPoint(
                x: labelCenterX
                    - direction * (halfTextWidth + Layout.externalLeaderTextSpacing),
                y: layout.labelY
            )
            let radialPoint = externalLeaderElbow(
                center: center,
                outerRadius: outerRadius,
                angle: layout.sector.midAngle,
                labelY: layout.labelY
            )
            var leaderPath = Path()
            leaderPath.move(to: anchorPoint)
            if usesRoutingLane {
                let radialStub = point(
                    center: center,
                    radius: outerRadius + Layout.externalLeaderMinimumLength,
                    angle: layout.sector.midAngle
                )
                leaderPath.addLine(to: radialStub)
                leaderPath.addLine(
                    to: CGPoint(x: routingX, y: layout.labelY)
                )
            } else {
                leaderPath.addLine(to: radialPoint)
            }
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

    private func externalLabelText(
        for layout: SpeedZoneExternalLabelLayout
    ) -> Text {
        Text(zoneLabel(for: layout.sector.share))
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.black)
    }

    private func distributedExternalLabels(
        _ layouts: [SpeedZoneExternalLabelLayout],
        centerY: CGFloat
    ) -> [SpeedZoneExternalLabelLayout] {
        guard !layouts.isEmpty else { return [] }
        var result = layouts.sorted { $0.naturalY < $1.naturalY }
        let positions = OutwardVerticalLabelLayout.positions(
            naturalYPositions: result.map(\.naturalY),
            centerY: centerY,
            spacing: Layout.externalLabelSpacing
        )
        for index in result.indices {
            result[index].labelY = positions[index]
        }
        return result
    }

    private func externalLeaderElbow(
        center: CGPoint,
        outerRadius: CGFloat,
        angle: Double,
        labelY: CGFloat
    ) -> CGPoint {
        RadialLeaderGeometry.elbow(
            center: center,
            outerRadius: outerRadius,
            minimumLength: Layout.externalLeaderMinimumLength,
            angle: angle,
            labelY: labelY
        )
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

enum OutwardVerticalLabelLayout {
    static func positions(
        naturalYPositions: [CGFloat],
        centerY: CGFloat,
        spacing: CGFloat
    ) -> [CGFloat] {
        guard !naturalYPositions.isEmpty else { return [] }
        var positions = naturalYPositions
        let upperIndices = positions.indices.filter {
            naturalYPositions[$0] < centerY
        }
        let lowerIndices = positions.indices.filter {
            naturalYPositions[$0] >= centerY
        }

        if upperIndices.count > 1 {
            for offset in stride(from: upperIndices.count - 2, through: 0, by: -1) {
                let index = upperIndices[offset]
                let lowerIndex = upperIndices[offset + 1]
                positions[index] = min(
                    naturalYPositions[index],
                    positions[lowerIndex] - spacing
                )
            }
        }

        if lowerIndices.count > 1 {
            for offset in 1..<lowerIndices.count {
                let index = lowerIndices[offset]
                let upperIndex = lowerIndices[offset - 1]
                positions[index] = max(
                    naturalYPositions[index],
                    positions[upperIndex] + spacing
                )
            }
        }

        if let upperIndex = upperIndices.last,
           let lowerIndex = lowerIndices.first {
            let gap = positions[lowerIndex] - positions[upperIndex]
            if gap < spacing {
                let offset = spacing - gap
                for index in upperIndices {
                    positions[index] -= offset
                }
            }
        }

        return positions
    }
}

struct SpeedZoneChartGeometry {
    let height: CGFloat
    let centerY: CGFloat

    static func make(
        baseHeight: CGFloat,
        labelYPositions: [CGFloat],
        verticalMargin: CGFloat
    ) -> SpeedZoneChartGeometry {
        let minimumLabelY = labelYPositions.min() ?? verticalMargin
        let maximumLabelY = labelYPositions.max() ?? baseHeight - verticalMargin
        let topInset = max(0, verticalMargin - minimumLabelY)
        let bottomInset = max(
            0,
            maximumLabelY + verticalMargin - baseHeight
        )
        return SpeedZoneChartGeometry(
            height: baseHeight + topInset + bottomInset,
            centerY: baseHeight / 2 + topInset
        )
    }
}

enum RadialLeaderGeometry {
    static func elbow(
        center: CGPoint,
        outerRadius: CGFloat,
        minimumLength: CGFloat,
        angle: Double,
        labelY: CGFloat
    ) -> CGPoint {
        let sine = CGFloat(sin(angle))
        let minimumRadius = outerRadius + minimumLength
        guard abs(sine) > .ulpOfOne else {
            return point(center: center, radius: minimumRadius, angle: angle)
        }
        let requiredRadius = (labelY - center.y) / sine
        return point(
            center: center,
            radius: max(minimumRadius, requiredRadius),
            angle: angle
        )
    }

    private static func point(
        center: CGPoint,
        radius: CGFloat,
        angle: Double
    ) -> CGPoint {
        CGPoint(
            x: center.x + radius * CGFloat(cos(angle)),
            y: center.y + radius * CGFloat(sin(angle))
        )
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
