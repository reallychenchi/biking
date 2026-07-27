import Foundation

enum RideFormatting {
    static func distance(_ meters: Double) -> String {
        String(format: "%.2f km", locale: Locale(identifier: "en_US_POSIX"), meters / 1_000)
    }

    static func distanceValue(_ meters: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), meters / 1_000)
    }

    static func speed(_ metersPerSecond: Double) -> String {
        String(format: "%.2f km/h", locale: Locale(identifier: "en_US_POSIX"), metersPerSecond * 3.6)
    }

    static func speedValue(_ metersPerSecond: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), metersPerSecond * 3.6)
    }

    static func elevation(_ meters: Double?) -> String {
        guard let value = elevationValue(meters) else { return "—" }
        return "\(value) m"
    }

    static func elevationRange(minimumMeters: Double?, maximumMeters: Double?) -> String {
        guard let minimum = elevationValue(minimumMeters),
              let maximum = elevationValue(maximumMeters) else {
            return "—"
        }
        return "\(minimum)–\(maximum) m"
    }

    static func liveDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        if total >= 3_600 {
            return String(format: "%02d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func fullDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
    }

    static func date(_ date: Date) -> String {
        formatter("yyyy-MM-dd").string(from: date)
    }

    static func time(_ date: Date) -> String {
        formatter("HH:mm").string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        formatter("yyyy-MM-dd HH:mm:ss").string(from: date)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }

    private static func elevationValue(_ meters: Double?) -> String? {
        guard let meters, meters.isFinite else { return nil }
        let rounded = meters.rounded()
        let normalized = rounded == 0 ? 0 : rounded
        return String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), normalized)
            .replacingOccurrences(of: "-", with: "−")
    }
}
