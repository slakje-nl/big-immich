import Foundation
import ImmichAPI

/// On-disk cache of the albums grid, keyed by sort order, so the "all albums" screen paints
/// instantly from the previous launch while the fresh list loads in the background. Albums are
/// created rarely, so the cached list is almost always already complete; any new ones appear
/// once the background refresh finishes.
final nonisolated class AlbumsListCache: @unchecked Sendable {
    static let shared = AlbumsListCache()

    private let store: CodableDiskCache<[AlbumSummary]>

    init(store: CodableDiskCache<[AlbumSummary]> = CodableDiskCache(name: "AlbumsList")) {
        self.store = store
    }

    func cached(order: AlbumsOrder) -> [AlbumSummary]? {
        store.value(forKey: order.rawValue)
    }

    func set(order: AlbumsOrder, albums: [AlbumSummary]) {
        store.store(albums, forKey: order.rawValue)
    }

    func totalSizeBytes() -> Int64 {
        store.totalSizeBytes()
    }

    func clear() {
        store.clear()
    }
}
