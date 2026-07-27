import MapKit
import OSLog
import SwiftUI
import UIKit

@MainActor
final class RideRouteSnapshotRenderer {
    static let shared = RideRouteSnapshotRenderer()

    private static let cacheVersion = "v2"
    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCache: RideRouteSnapshotDiskCache

    private init(diskCache: RideRouteSnapshotDiskCache = .shared) {
        self.diskCache = diskCache
        memoryCache.countLimit = 100
    }

    func image(for ride: RideRecord, size: CGSize, appearance: AppAppearance) async -> UIImage? {
        let scale = UIScreen.main.scale
        let cacheKey = Self.cacheKey(for: ride, size: size, scale: scale, appearance: appearance)
        let memoryCacheKey = cacheKey as NSString
        if let cachedImage = memoryCache.object(forKey: memoryCacheKey) {
            return cachedImage
        }

        do {
            if let cachedData = try await diskCache.data(forKey: cacheKey) {
                if let cachedImage = UIImage(data: cachedData, scale: scale) {
                    memoryCache.setObject(cachedImage, forKey: memoryCacheKey)
                    AppLog.history.info("读取历史轨迹缩略图磁盘缓存成功 rideID=\(ride.id.uuidString, privacy: .public)")
                    return cachedImage
                }
                AppLog.history.warning("历史轨迹缩略图磁盘缓存无效，将重新生成 rideID=\(ride.id.uuidString, privacy: .public)")
            }
        } catch {
            AppLog.history.warning("读取历史轨迹缩略图磁盘缓存失败，将重新生成 rideID=\(ride.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }

        let geometry = RideRouteGeometry(points: ride.points)
        guard let mapRect = geometry.mapRect else { return nil }

        let options = MKMapSnapshotter.Options()
        options.mapRect = mapRect
        options.size = size
        options.scale = scale
        options.mapType = .standard
        options.showsBuildings = false
        options.pointOfInterestFilter = .excludingAll
        let traitCollection = UITraitCollection(userInterfaceStyle: appearance.userInterfaceStyle)
        options.traitCollection = traitCollection

        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            try Task.checkCancellation()
            let image = drawRoute(geometry, on: snapshot, size: size, traitCollection: traitCollection)
            memoryCache.setObject(image, forKey: memoryCacheKey)
            if let imageData = image.pngData() {
                Task { [diskCache] in
                    do {
                        try await diskCache.store(imageData, forKey: cacheKey)
                        AppLog.history.info("历史轨迹缩略图磁盘缓存保存成功 rideID=\(ride.id.uuidString, privacy: .public)")
                    } catch {
                        AppLog.history.warning("历史轨迹缩略图磁盘缓存保存失败 rideID=\(ride.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                    }
                }
            } else {
                AppLog.history.warning("历史轨迹缩略图 PNG 编码失败 rideID=\(ride.id.uuidString, privacy: .public)")
            }
            AppLog.history.info("历史轨迹缩略图生成成功 rideID=\(ride.id.uuidString, privacy: .public)")
            return image
        } catch is CancellationError {
            return nil
        } catch {
            AppLog.history.warning("历史轨迹缩略图生成失败 rideID=\(ride.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func cacheKey(
        for ride: RideRecord,
        size: CGSize,
        scale: CGFloat,
        appearance: AppAppearance
    ) -> String {
        let updatedAtMilliseconds = Int64(ride.updatedAt.timeIntervalSince1970 * 1_000)
        return "\(cacheVersion)-\(appearance.rawValue)-\(ride.id.uuidString)-\(updatedAtMilliseconds)-\(Int(size.width))x\(Int(size.height))-@\(Int(scale))x"
    }

    private func drawRoute(
        _ geometry: RideRouteGeometry,
        on snapshot: MKMapSnapshotter.Snapshot,
        size: CGSize,
        traitCollection: UITraitCollection
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            snapshot.image.draw(at: .zero)

            context.cgContext.setLineCap(.round)
            context.cgContext.setLineJoin(.round)
            context.cgContext.setLineWidth(4)
            let routeColor = UIColor(AppTheme.accentForeground).resolvedColor(with: traitCollection)
            context.cgContext.setStrokeColor(routeColor.cgColor)

            for segment in geometry.segments where segment.count >= 2 {
                let path = UIBezierPath()
                path.move(to: snapshot.point(for: segment[0]))
                for coordinate in segment.dropFirst() {
                    path.addLine(to: snapshot.point(for: coordinate))
                }
                path.stroke()
            }

            if let start = geometry.coordinates.first {
                drawMarker(at: snapshot.point(for: start), color: .systemGreen, in: context.cgContext)
            }
            if let end = geometry.coordinates.last, geometry.coordinates.count > 1 {
                drawMarker(at: snapshot.point(for: end), color: .systemRed, in: context.cgContext)
            }
        }
    }

    private func drawMarker(at point: CGPoint, color: UIColor, in context: CGContext) {
        let markerSize: CGFloat = 9
        let markerRect = CGRect(
            x: point.x - markerSize / 2,
            y: point.y - markerSize / 2,
            width: markerSize,
            height: markerSize
        )
        context.setFillColor(color.cgColor)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2)
        context.fillEllipse(in: markerRect)
        context.strokeEllipse(in: markerRect)
    }
}
