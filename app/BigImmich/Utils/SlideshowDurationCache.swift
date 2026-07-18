import Foundation
import ImmichAPI

/// The cached inputs for an album's slideshow duration. The final minutes are recomputed
/// from these plus the current image interval, so changing the interval is still respected.
struct SlideshowDurationInfo: Codable {
    /// Change token (album asset count + last-modified timestamp); a mismatch invalidates.
    let token: String
    let videoCount: Int
    let videoDurationMilliseconds: Int
}

/// Persists per-album duration inputs in `UserDefaults`, so revisiting an album's details
/// screen doesn't re-fetch its videos unless the album changed.
enum SlideshowDurationCache {
    static func token(assetCount: Int?, lastModifiedAssetTimestamp: String?) -> String {
        "\(assetCount ?? -1)|\(lastModifiedAssetTimestamp ?? "")"
    }

    private static func key(_ albumID: AlbumID) -> String {
        "slideshowDuration_\(albumID.string)"
    }

    /// Returns the cached info only if its token matches (i.e. the album is unchanged).
    static func get(albumID: AlbumID, token: String) -> SlideshowDurationInfo? {
        guard let data = UserDefaults.standard.data(forKey: key(albumID)),
              let info = try? JSONDecoder().decode(SlideshowDurationInfo.self, from: data),
              info.token == token
        else {
            return nil
        }
        return info
    }

    static func set(albumID: AlbumID, info: SlideshowDurationInfo) {
        guard let data = try? JSONEncoder().encode(info) else { return }
        UserDefaults.standard.set(data, forKey: key(albumID))
    }
}
