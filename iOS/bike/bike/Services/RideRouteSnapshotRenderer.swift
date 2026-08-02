import MapKit
import OSLog
import SwiftUI
import UIKit

@MainActor
final class RideRouteSnapshotRenderer {
    static let shared = RideRouteSnapshotRenderer()

    private static let cacheVersion = "v3"
    private static let snapshotRetryDelay: Duration = .seconds(1)
    private static let snapshotTimeout: Duration = .seconds(4)
    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCache: RideRouteSnapshotDiskCache
    private let snapshotRequestQueue = MapSnapshotRequestQueue()

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

        let image: UIImage
        do {
            let snapshot = try await createSnapshot(options: options)
            try Task.checkCancellation()
            image = drawRoute(geometry, on: snapshot, size: size, traitCollection: traitCollection)
        } catch is CancellationError {
            return nil
        } catch {
            AppLog.history.warning("历史轨迹缩略图地图快照不可用，使用本地轨迹缩略图 rideID=\(ride.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            image = drawRouteFallback(geometry, size: size, traitCollection: traitCollection)
        }

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
    }

    private func createSnapshot(options: MKMapSnapshotter.Options) async throws -> MKMapSnapshotter.Snapshot {
        do {
            return try await performSnapshot(options: options)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLog.history.warning("历史轨迹缩略图地图快照失败，将重试一次 error=\(error.localizedDescription, privacy: .public)")
            try await Task.sleep(for: Self.snapshotRetryDelay)
            return try await performSnapshot(options: options)
        }
    }

    private func performSnapshot(options: MKMapSnapshotter.Options) async throws -> MKMapSnapshotter.Snapshot {
        await snapshotRequestQueue.waitForTurn()
        do {
            let snapshot = try await snapshotWithTimeout(options: options)
            await snapshotRequestQueue.finishTurn()
            return snapshot
        } catch {
            await snapshotRequestQueue.finishTurn()
            throw error
        }
    }

    private func snapshotWithTimeout(options: MKMapSnapshotter.Options) async throws -> MKMapSnapshotter.Snapshot {
        let snapshotter = MKMapSnapshotter(options: options)
        let snapshotTask = Task { @MainActor [snapshotter] in
            try Task.checkCancellation()
            return try await snapshotter.start()
        }

        defer {
            snapshotTask.cancel()
            snapshotter.cancel()
        }

        return try await withThrowingTaskGroup(of: MKMapSnapshotter.Snapshot.self) { group in
            group.addTask {
                try await snapshotTask.value
            }
            group.addTask {
                try await Task.sleep(for: Self.snapshotTimeout)
                throw MapSnapshotRequestError.timedOut
            }

            guard let snapshot = try await group.next() else {
                throw MapSnapshotRequestError.timedOut
            }
            group.cancelAll()
            return snapshot
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

    private func drawRouteFallback(
        _ geometry: RideRouteGeometry,
        size: CGSize,
        traitCollection: UITraitCollection
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let backgroundColor = UIColor(AppTheme.pageBackground).resolvedColor(with: traitCollection)
            context.cgContext.setFillColor(backgroundColor.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))

            guard let mapRect = geometry.mapRect else { return }
            let routeColor = UIColor(AppTheme.accentForeground).resolvedColor(with: traitCollection)
            context.cgContext.setLineCap(.round)
            context.cgContext.setLineJoin(.round)
            context.cgContext.setLineWidth(4)
            context.cgContext.setStrokeColor(routeColor.cgColor)

            for segment in geometry.segments where segment.count >= 2 {
                let path = UIBezierPath()
                path.move(to: fallbackPoint(for: segment[0], in: mapRect, size: size))
                for coordinate in segment.dropFirst() {
                    path.addLine(to: fallbackPoint(for: coordinate, in: mapRect, size: size))
                }
                path.stroke()
            }

            if let start = geometry.coordinates.first {
                drawMarker(at: fallbackPoint(for: start, in: mapRect, size: size), color: .systemGreen, in: context.cgContext)
            }
            if let end = geometry.coordinates.last, geometry.coordinates.count > 1 {
                drawMarker(at: fallbackPoint(for: end, in: mapRect, size: size), color: .systemRed, in: context.cgContext)
            }
        }
    }

    private func fallbackPoint(for coordinate: CLLocationCoordinate2D, in mapRect: MKMapRect, size: CGSize) -> CGPoint {
        let mapPoint = MKMapPoint(coordinate)
        let x = (mapPoint.x - mapRect.origin.x) / mapRect.size.width
        let y = (mapPoint.y - mapRect.origin.y) / mapRect.size.height
        return CGPoint(x: size.width * x, y: size.height * y)
    }
}

private enum MapSnapshotRequestError: Error {
    case timedOut
}

private actor MapSnapshotRequestQueue {
    private var isProcessing = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func waitForTurn() async {
        if !isProcessing {
            isProcessing = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func finishTurn() {
        if waiters.isEmpty {
            isProcessing = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
