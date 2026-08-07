import MapKit
import SwiftUI

struct RideRouteView: View {
    enum RouteStyle {
        case solid
        case speedGradient
    }

    private let geometry: RideRouteGeometry
    private let initialMapPosition: MapCameraPosition
    private let routeStyle: RouteStyle

    init(points: [TrackPoint], routeStyle: RouteStyle = .solid) {
        let geometry = RideRouteGeometry(points: points)
        self.geometry = geometry
        self.initialMapPosition = geometry.mapRect.map(MapCameraPosition.rect) ?? .automatic
        self.routeStyle = routeStyle
    }

    var body: some View {
        Group {
            if geometry.coordinates.isEmpty {
                ContentUnavailableView("无轨迹数据", systemImage: "map")
            } else {
                Map(initialPosition: initialMapPosition) {
                    routeOverlays
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

    @MapContentBuilder
    private var routeOverlays: some MapContent {
        switch routeStyle {
        case .solid:
            solidRouteOverlays
        case .speedGradient:
            speedGradientRouteOverlays
        }
    }

    @MapContentBuilder
    private var solidRouteOverlays: some MapContent {
        ForEach(Array(geometry.segments.enumerated()), id: \.offset) { _, coords in
            if coords.count >= 2 {
                MapPolyline(coordinates: coords)
                    .stroke(AppTheme.accentForeground, lineWidth: 4)
            }
        }
    }

    @MapContentBuilder
    private var speedGradientRouteOverlays: some MapContent {
        if geometry.speedSegments.isEmpty {
            solidRouteOverlays
        } else {
            ForEach(Array(geometry.speedSegments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(
                        RideSpeedZoneStyle.color(
                            forSpeedMetersPerSecond: segment.speedMetersPerSecond
                        ),
                        lineWidth: 4
                    )
            }
        }
    }
}
