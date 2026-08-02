import CoreLocation

enum MapCoordinateConverter {
    private static let chinaMinimumLatitude = 0.8293
    private static let chinaMaximumLatitude = 55.8271
    private static let chinaMinimumLongitude = 72.004
    private static let chinaMaximumLongitude = 137.8347
    private static let semiMajorAxis = 6_378_245.0
    private static let eccentricitySquared = 0.006_693_421_622_965_943_23

    /// Converts a WGS-84 coordinate to the GCJ-02 coordinate required by the mainland China map base layer.
    /// Coordinates outside mainland China remain unchanged because GCJ-02 does not apply there.
    static func mapDisplayCoordinate(for coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isWithinMainlandChina(coordinate) else { return coordinate }

        let latitudeOffset = transformedLatitude(
            longitudeOffset: coordinate.longitude - 105,
            latitudeOffset: coordinate.latitude - 35
        )
        let longitudeOffset = transformedLongitude(
            longitudeOffset: coordinate.longitude - 105,
            latitudeOffset: coordinate.latitude - 35
        )
        let latitudeRadians = coordinate.latitude * .pi / 180
        let sineLatitude = sin(latitudeRadians)
        let magic = 1 - eccentricitySquared * sineLatitude * sineLatitude
        let squareRootMagic = sqrt(magic)
        let adjustedLatitude = latitudeOffset * 180 / ((semiMajorAxis * (1 - eccentricitySquared)) / (magic * squareRootMagic) * .pi)
        let adjustedLongitude = longitudeOffset * 180 / (semiMajorAxis / squareRootMagic * cos(latitudeRadians) * .pi)

        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + adjustedLatitude,
            longitude: coordinate.longitude + adjustedLongitude
        )
    }

    private static func isWithinMainlandChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude >= chinaMinimumLatitude && coordinate.latitude <= chinaMaximumLatitude
            && coordinate.longitude >= chinaMinimumLongitude && coordinate.longitude <= chinaMaximumLongitude
    }

    private static func transformedLatitude(longitudeOffset x: Double, latitudeOffset y: Double) -> Double {
        var result = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        result += (20 * sin(y * .pi) + 40 * sin(y / 3 * .pi)) * 2 / 3
        result += (160 * sin(y / 12 * .pi) + 320 * sin(y * .pi / 30)) * 2 / 3
        return result
    }

    private static func transformedLongitude(longitudeOffset x: Double, latitudeOffset y: Double) -> Double {
        var result = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        result += (20 * sin(x * .pi) + 40 * sin(x / 3 * .pi)) * 2 / 3
        result += (150 * sin(x / 12 * .pi) + 300 * sin(x / 30 * .pi)) * 2 / 3
        return result
    }
}
