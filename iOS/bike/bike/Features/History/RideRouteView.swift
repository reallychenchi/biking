import MapKit
import SwiftUI

struct RideRouteView: View {
    private let segments: [[CLLocationCoordinate2D]]
    private let allCoordinates: [CLLocationCoordinate2D]
    private let initialMapPosition: MapCameraPosition

    init(ride: RideRecord) {
        let segments = Self.makeSegments(from: ride.points)
        let allCoordinates = segments.flatMap { $0 }
        self.segments = segments
        self.allCoordinates = allCoordinates
        self.initialMapPosition = Self.mapPosition(for: allCoordinates)
    }

    private static func makeSegments(from points: [TrackPoint]) -> [[CLLocationCoordinate2D]] {
        let sorted = points.sorted { $0.sequence < $1.sequence }
        guard !sorted.isEmpty else { return [] }
        var result: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = [sorted[0].coordinate]
        var currentSegment = sorted[0].segmentIndex
        for point in sorted.dropFirst() {
            if point.segmentIndex != currentSegment {
                result.append(current)
                current = []
                currentSegment = point.segmentIndex
            }
            current.append(point.coordinate)
        }
        result.append(current)
        return result
    }

    private static func mapPosition(for coordinates: [CLLocationCoordinate2D]) -> MapCameraPosition {
        let points = coordinates.map { MKMapPoint($0) }
        guard !points.isEmpty else { return .automatic }
        let minX = points.map(\.x).min()!
        let maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!
        let maxY = points.map(\.y).max()!
        let padding = 0.2
        let width = max(maxX - minX, 200)
        let height = max(maxY - minY, 200)
        let rect = MKMapRect(
            x: minX - width * padding,
            y: minY - height * padding,
            width: width * (1 + 2 * padding),
            height: height * (1 + 2 * padding)
        )
        return .rect(rect)
    }

    var body: some View {
        Group {
            if allCoordinates.isEmpty {
                ContentUnavailableView("无轨迹数据", systemImage: "map")
            } else {
                Map(initialPosition: initialMapPosition) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, coords in
                        if coords.count >= 2 {
                            MapPolyline(coordinates: coords)
                                .stroke(AppTheme.accent, lineWidth: 4)
                        }
                    }
                    if let start = allCoordinates.first {
                        Annotation("出发", coordinate: start, anchor: .bottom) {
                            Image(systemName: "circle.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                        }
                    }
                    if let end = allCoordinates.last, allCoordinates.count > 1 {
                        Annotation("到达", coordinate: end, anchor: .bottom) {
                            Image(systemName: "flag.fill")
                                .font(.title3)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .mapStyle(.standard)
            }
        }
    }
}
