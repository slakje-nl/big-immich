import Foundation
import ImmichAPI

/// On-disk cache of the `Album` metadata shown on the details screen (name, thumbnail id,
/// asset count, change token), so revisiting an album paints its header instantly from the
/// previous visit while the fresh copy loads in the background. Albums change rarely, so the
/// cached copy is almost always still correct.
final nonisolated class AlbumDetailCache: @unchecked Sendable {
    static let shared = AlbumDetailCache()

    private let store: CodableDiskCache<Album>

    init(store: CodableDiskCache<Album> = CodableDiskCache(name: "AlbumDetail")) {
        self.store = store
    }

    func cached(albumID: AlbumID) -> Album? {
        store.value(forKey: albumID.string)
    }

    func set(_ album: Album) {
        store.store(album, forKey: album.id.string)
    }

    func totalSizeBytes() -> Int64 {
        store.totalSizeBytes()
    }

    func clear() {
        store.clear()
    }
}
