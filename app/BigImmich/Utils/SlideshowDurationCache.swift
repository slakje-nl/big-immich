import Foundation
import ImmichAPI

/// The cached inputs for an album's slideshow duration. The final minutes are recomputed
/// from these plus the current image interval, so changing the interval is still respected.
struct SlideshowDurationInfo {
    /// Change token (album asset count + last-modified timestamp); a mismatch invalidates.
    let token: String
    let videoCount: Int
    let videoDurationMilliseconds: Int
}

/// In-memory, per-session cache of album duration inputs, so revisiting an album's details
/// within the same session doesn't re-fetch its videos unless the album changed. Not
/// persisted: album/asset changes aren't reliably detectable across launches, so we start
/// fresh each launch rather than risk a stale number.
actor SlideshowDurationCache {
    static let shared = SlideshowDurationCache()

    private var entries: [AlbumID: SlideshowDurationInfo] = [:]

    nonisolated static func token(
        assetCount: Int?,
        lastModifiedAssetTimestamp: String?
    ) -> String {
        "\(assetCount ?? -1)|\(lastModifiedAssetTimestamp ?? "")"
    }

    /// Returns the cached info only if its token matches (i.e. the album is unchanged).
    func get(albumID: AlbumID, token: String) -> SlideshowDurationInfo? {
        guard let info = entries[albumID], info.token == token else { return nil }
        return info
    }

    func set(albumID: AlbumID, info: SlideshowDurationInfo) {
        entries[albumID] = info
    }
}
