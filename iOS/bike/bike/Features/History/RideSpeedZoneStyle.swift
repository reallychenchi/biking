import SwiftUI
import UIKit

enum RideSpeedZoneStyle {
    static let colors = [
        Color(red: 0.93, green: 0.11, blue: 0.20),
        Color(red: 0.94, green: 0.30, blue: 0.12),
        Color(red: 0.90, green: 0.52, blue: 0.10),
        Color(red: 0.70, green: 0.68, blue: 0.10),
        Color(red: 0.38, green: 0.68, blue: 0.20),
        Color(red: 0.12, green: 0.62, blue: 0.32)
    ]

    static func color(for zoneID: Int) -> Color {
        guard colors.indices.contains(zoneID) else {
            assertionFailure("Missing speed zone color")
            return AppTheme.secondaryText
        }
        return colors[zoneID]
    }

    static func color(forSpeedMetersPerSecond speedMetersPerSecond: Double) -> Color {
        let kilometersPerHour = max(0, speedMetersPerSecond * 3.6)
        let zones = RideSpeedAnalysis.zones
        guard let firstZone = zones.first,
              let lastZone = zones.last else {
            assertionFailure("Missing speed zones")
            return AppTheme.secondaryText
        }

        let firstUpperBound = firstZone.upperBoundKilometersPerHour ?? 0
        guard kilometersPerHour >= firstUpperBound else {
            return color(for: firstZone.id)
        }

        for index in zones.indices.dropFirst() {
            let zone = zones[index]
            if let upperBound = zone.upperBoundKilometersPerHour,
               kilometersPerHour < upperBound {
                let lowerColor = color(for: zones[index - 1].id)
                let upperColor = color(for: zone.id)
                let progress = normalizedProgress(
                    value: kilometersPerHour,
                    lowerBound: zone.lowerBoundKilometersPerHour,
                    upperBound: upperBound
                )
                return lowerColor.interpolated(to: upperColor, progress: progress)
            }
        }

        return color(for: lastZone.id)
    }

    private static func normalizedProgress(
        value: Double,
        lowerBound: Double,
        upperBound: Double
    ) -> Double {
        guard upperBound > lowerBound else { return 0 }
        return min(1, max(0, (value - lowerBound) / (upperBound - lowerBound)))
    }
}

private extension Color {
    func interpolated(to target: Color, progress: Double) -> Color {
        let start = components
        let end = target.components
        let clampedProgress = min(1, max(0, progress))
        return Color(
            red: start.red + (end.red - start.red) * clampedProgress,
            green: start.green + (end.green - start.green) * clampedProgress,
            blue: start.blue + (end.blue - start.blue) * clampedProgress,
            opacity: start.opacity + (end.opacity - start.opacity) * clampedProgress
        )
    }

    private var components: ColorComponents {
        #if canImport(UIKit)
        let resolved = UIColor(self).cgColor.components ?? []
        let colorSpaceModel = UIColor(self).cgColor.colorSpace?.model
        if colorSpaceModel == .monochrome, resolved.count >= 2 {
            return ColorComponents(
                red: resolved[0],
                green: resolved[0],
                blue: resolved[0],
                opacity: resolved[1]
            )
        }
        if resolved.count >= 4 {
            return ColorComponents(
                red: resolved[0],
                green: resolved[1],
                blue: resolved[2],
                opacity: resolved[3]
            )
        }
        #endif

        assertionFailure("Unable to resolve color components")
        return ColorComponents(red: 0, green: 0, blue: 0, opacity: 1)
    }
}

private struct ColorComponents {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let opacity: CGFloat
}
