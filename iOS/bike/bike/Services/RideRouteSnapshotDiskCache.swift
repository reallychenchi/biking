import Foundation

actor RideRouteSnapshotDiskCache {
    static let shared = RideRouteSnapshotDiskCache()

    private static let directoryName = "RideRouteSnapshots"
    private let directoryURL: URL
    private let fileManager: FileManager

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            self.directoryURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(Self.directoryName, isDirectory: true)
        }
    }

    func data(forKey key: String) throws -> Data? {
        let fileURL = fileURL(forKey: key)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        return try Data(contentsOf: fileURL)
    }

    func store(_ data: Data, forKey key: String) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL(forKey: key), options: .atomic)
    }

    private func fileURL(forKey key: String) -> URL {
        directoryURL.appendingPathComponent(key).appendingPathExtension("png")
    }
}
