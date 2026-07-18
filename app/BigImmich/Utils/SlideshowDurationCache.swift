import Foundation
import ImmichAPI

/// The cached inputs for an album's slideshow duration and item counts. The final minutes are
/// recomputed from these plus the current image interval, so changing the interval is still
/// respected.
nonisolated struct SlideshowDurationInfo: Codable, Sendable {
    /// Change token (album asset count + last-modified timestamp); a mismatch invalidates.
    let token: String
    /// The album's total asset count, so the image count can be shown without a fresh fetch.
    let assetCount: Int?
    let videoCount: Int
    let videoDurationMilliseconds: Int
}

/// On-disk cache of album duration inputs, so the details screen can paint the item counts and
/// runtime instantly from the previous visit and only re-fetch the album's videos when the
/// album actually changed. Every visit still re-reads the album itself, so a changed album
/// (token mismatch) refreshes in the background — the cache only avoids the redundant work.
final nonisolated class SlideshowDurationCache: @unchecked Sendable {
    static let shared = SlideshowDurationCache()

    private let store: CodableDiskCache<SlideshowDurationInfo>

    init(store: CodableDiskCache<SlideshowDurationInfo> = CodableDiskCache(name: "AlbumDuration")) {
        self.store = store
    }

    nonisolated static func token(
        assetCount: Int?,
        lastModifiedAssetTimestamp: String?
    ) -> String {
        "\(assetCount ?? -1)|\(lastModifiedAssetTimestamp ?? "")"
    }

    /// Any cached info, regardless of freshness — used to paint the screen instantly before
    /// the album has been re-fetched.
    func cached(albumID: AlbumID) -> SlideshowDurationInfo? {
        store.value(forKey: albumID.string)
    }

    /// Cached info only if its token matches (i.e. the album is unchanged), letting the caller
    /// skip the video fetch entirely.
    func fresh(albumID: AlbumID, token: String) -> SlideshowDurationInfo? {
        guard let info = cached(albumID: albumID), info.token == token else { return nil }
        return info
    }

    func set(albumID: AlbumID, info: SlideshowDurationInfo) {
        store.store(info, forKey: albumID.string)
    }

    func totalSizeBytes() -> Int64 {
        store.totalSizeBytes()
    }

    func clear() {
        store.clear()
    }
}
