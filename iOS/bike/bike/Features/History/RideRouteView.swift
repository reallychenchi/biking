import MapKit
import SwiftUI

struct RideRouteView: View {
    private let geometry: RideRouteGeometry
    private let initialMapPosition: MapCameraPosition

    init(ride: RideRecord) {
        let geometry = RideRouteGeometry(points: ride.points)
        self.geometry = geometry
        self.initialMapPosition = geometry.mapRect.map(MapCameraPosition.rect) ?? .automatic
    }

    var body: some View {
        Group {
            if geometry.coordinates.isEmpty {
                ContentUnavailableView("无轨迹数据", systemImage: "map")
            } else {
                Map(initialPosition: initialMapPosition) {
                    ForEach(Array(geometry.segments.enumerated()), id: \.offset) { _, coords in
                        if coords.count >= 2 {
                            MapPolyline(coordinates: coords)
                                .stroke(AppTheme.accent, lineWidth: 4)
                        }
                    }
                    if let start = geometry.coordinates.first {
                        Annotation("出发", coordinate: start, anchor: .bottom) {
                            Image(systemName: "circle.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                        }
                    }
                    if let end = geometry.coordinates.last, geometry.coordinates.count > 1 {
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
