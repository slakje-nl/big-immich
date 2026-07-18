import Foundation

/// A disk cache that can report its footprint and be emptied. Lets the Settings
/// "Cache size" / "Clear cache" controls treat every cache uniformly.
protocol DiskCacheReporting: Sendable {
    func totalSizeBytes() -> Int64
    func clear()
}

extension ImageDiskCache: DiskCacheReporting {}
extension AlbumDetailCache: DiskCacheReporting {}
extension AlbumsListCache: DiskCacheReporting {}
extension AlbumAssetsCache: DiskCacheReporting {}

/// Single entry point for the app's on-disk caches, so the Settings "Cache size" field and
/// "Clear cache" button cover everything the app stores — image bytes plus the album/duration
/// metadata caches — rather than just one of them.
enum AppCaches {
    static var all: [DiskCacheReporting] {
        [
            ImageDiskCache.shared,
            AlbumDetailCache.shared,
            AlbumsListCache.shared,
            AlbumAssetsCache.shared
        ]
    }

    /// Combined size of every cache on disk.
    static func totalSizeBytes() -> Int64 {
        all.reduce(0) { $0 + $1.totalSizeBytes() }
    }

    /// Empties every cache.
    static func clear() {
        for cache in all {
            cache.clear()
        }
    }
}
