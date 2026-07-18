import Foundation
import ImmichAPI

/// On-disk cache of an album's asset list, so the asset grid and the slideshow can start from
/// the previous visit's snapshot instead of waiting on the `search/metadata` fetch every time.
/// The fresh list is loaded in the background and written back, so newly added assets converge
/// on the next visit — albums change rarely, so in practice the cached list is already correct.
final nonisolated class AlbumAssetsCache: @unchecked Sendable {
    static let shared = AlbumAssetsCache()

    private let store: CodableDiskCache<[AlbumAsset]>

    init(store: CodableDiskCache<[AlbumAsset]> = CodableDiskCache(name: "AlbumAssets")) {
        self.store = store
    }

    func cached(albumID: AlbumID) -> [AlbumAsset]? {
        store.value(forKey: albumID.string)
    }

    func set(albumID: AlbumID, assets: [AlbumAsset]) {
        store.store(assets, forKey: albumID.string)
    }

    func totalSizeBytes() -> Int64 {
        store.totalSizeBytes()
    }

    func clear() {
        store.clear()
    }
}
