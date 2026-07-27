import OSLog

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "cc.chenchi.bike"

    static let ride = Logger(subsystem: subsystem, category: "Ride")
    static let location = Logger(subsystem: subsystem, category: "Location")
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    static let history = Logger(subsystem: subsystem, category: "History")
}
