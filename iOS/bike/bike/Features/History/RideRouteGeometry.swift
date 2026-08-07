import MapKit

struct RideRouteGeometry {
    static let minimumMapSpan: Double = 200
    static let mapPaddingRatio: Double = 0.2
    static let maximumSpeedGradientStops = 96

    let segments: [[CLLocationCoordinate2D]]
    let speedGradientSegments: [RideRouteSpeedGradientSegment]
    let coordinates: [CLLocationCoordinate2D]
    let mapRect: MKMapRect?

    init(points: [TrackPoint]) {
        let sortedPoints = points.sorted { $0.sequence < $1.sequence }
        segments = Self.makeSegments(from: sortedPoints)
        speedGradientSegments = Self.makeSpeedGradientSegments(from: sortedPoints)
        coordinates = segments.flatMap { $0 }
        mapRect = Self.makeMapRect(for: coordinates)
    }

    private static func makeSegments(from points: [TrackPoint]) -> [[CLLocationCoordinate2D]] {
        guard let firstPoint = points.first else { return [] }

        var result: [[CLLocationCoordinate2D]] = []
        var currentSegment = [firstPoint.mapDisplayCoordinate]
        var currentSegmentIndex = firstPoint.segmentIndex

        for point in points.dropFirst() {
            if point.segmentIndex != currentSegmentIndex {
                result.append(currentSegment)
                currentSegment = []
                currentSegmentIndex = point.segmentIndex
            }
            currentSegment.append(point.mapDisplayCoordinate)
        }
        result.append(currentSegment)
        return result
    }

    private static func makeSpeedGradientSegments(from points: [TrackPoint]) -> [RideRouteSpeedGradientSegment] {
        guard points.count >= 2 else { return [] }

        var result: [RideRouteSpeedGradientSegment] = []
        var currentPoints: [TrackPoint] = []
        var currentSegmentIndex = points[points.startIndex].segmentIndex

        for point in points {
            if point.segmentIndex != currentSegmentIndex {
                appendSpeedGradientSegment(&result, points: currentPoints)
                currentPoints = []
                currentSegmentIndex = point.segmentIndex
            }
            currentPoints.append(point)
        }

        appendSpeedGradientSegment(&result, points: currentPoints)
        return result
    }

    private static func appendSpeedGradientSegment(
        _ result: inout [RideRouteSpeedGradientSegment],
        points: [TrackPoint]
    ) {
        guard let segment = makeSpeedGradientSegment(points: points) else { return }
        result.append(segment)
    }

    private static func makeSpeedGradientSegment(points: [TrackPoint]) -> RideRouteSpeedGradientSegment? {
        guard points.count >= 2 else { return nil }

        let coordinates = points.map(\.mapDisplayCoordinate)
        let cumulativeDistances = makeCumulativeDistances(for: coordinates)
        guard let totalDistance = cumulativeDistances.last,
              totalDistance > 0 else {
            return nil
        }

        var stops: [RideRouteSpeedGradientStop] = []
        for index in points.indices {
            let previous = index > points.startIndex ? points[points.index(before: index)] : nil
            let next = index < points.index(before: points.endIndex)
                ? points[points.index(after: index)]
                : nil
            guard let speedMetersPerSecond = RideSpeedAnomalyFilter.validSpeed(
                for: points[index],
                previous: previous,
                next: next
            ) else {
                continue
            }

            stops.append(
                RideRouteSpeedGradientStop(
                    location: cumulativeDistances[index] / totalDistance,
                    gradientStep: RideSpeedZoneStyle.gradientStep(
                        forSpeedMetersPerSecond: speedMetersPerSecond
                    )
                )
            )
        }

        let normalizedStops = normalizedGradientStops(stops)
        guard normalizedStops.count >= 2 else { return nil }
        return RideRouteSpeedGradientSegment(
            coordinates: coordinates,
            stops: compactGradientStops(normalizedStops)
        )
    }

    private static func makeCumulativeDistances(for coordinates: [CLLocationCoordinate2D]) -> [Double] {
        guard let firstCoordinate = coordinates.first else { return [] }

        var result = [0.0]
        var previousPoint = MKMapPoint(firstCoordinate)
        var cumulativeDistance = 0.0
        for coordinate in coordinates.dropFirst() {
            let point = MKMapPoint(coordinate)
            cumulativeDistance += previousPoint.distance(to: point)
            result.append(cumulativeDistance)
            previousPoint = point
        }
        return result
    }

    private static func normalizedGradientStops(
        _ stops: [RideRouteSpeedGradientStop]
    ) -> [RideRouteSpeedGradientStop] {
        guard var firstStop = stops.first,
              var lastStop = stops.last else {
            return []
        }

        var result = stops
        if firstStop.location > 0 {
            firstStop = RideRouteSpeedGradientStop(
                location: 0,
                gradientStep: firstStop.gradientStep
            )
            result.insert(firstStop, at: 0)
        }
        if lastStop.location < 1 {
            lastStop = RideRouteSpeedGradientStop(
                location: 1,
                gradientStep: lastStop.gradientStep
            )
            result.append(lastStop)
        }
        return result
    }

    private static func compactGradientStops(
        _ stops: [RideRouteSpeedGradientStop]
    ) -> [RideRouteSpeedGradientStop] {
        guard stops.count > maximumSpeedGradientStops else { return stops }

        let stride = Int(ceil(Double(stops.count - 2) / Double(maximumSpeedGradientStops - 2)))
        var result = [stops[stops.startIndex]]
        for stop in stops.dropFirst().dropLast().enumerated() where stop.offset.isMultiple(of: stride) {
            result.append(stop.element)
        }
        result.append(stops[stops.index(before: stops.endIndex)])
        return result
    }

    private static func makeMapRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect? {
        guard let firstCoordinate = coordinates.first else { return nil }

        var bounds = MKMapRect(origin: MKMapPoint(firstCoordinate), size: .init())
        for coordinate in coordinates.dropFirst() {
            let point = MKMapPoint(coordinate)
            bounds = bounds.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }

        let width = max(bounds.width, minimumMapSpan)
        let height = max(bounds.height, minimumMapSpan)
        let centeredBounds = MKMapRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
        return centeredBounds.insetBy(
            dx: -width * mapPaddingRatio,
            dy: -height * mapPaddingRatio
        )
    }
}

struct RideRouteSpeedGradientSegment {
    let coordinates: [CLLocationCoordinate2D]
    let stops: [RideRouteSpeedGradientStop]
}

struct RideRouteSpeedGradientStop {
    let location: Double
    let gradientStep: Int
}
