import MapKit

struct RideRouteGeometry {
    static let minimumMapSpan: Double = 200
    static let mapPaddingRatio: Double = 0.2

    let segments: [[CLLocationCoordinate2D]]
    let coordinates: [CLLocationCoordinate2D]
    let mapRect: MKMapRect?

    init(points: [TrackPoint]) {
        let sortedPoints = points.sorted { $0.sequence < $1.sequence }
        segments = Self.makeSegments(from: sortedPoints)
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
