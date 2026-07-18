import Foundation
import ImmichAPI

/// Total slideshow runtime, in minutes rounded up.
///
/// Images all play for the fixed `imageInterval`, so only their count is needed —
/// never their metadata. Videos play for their own length. This lets the album
/// details screen compute duration by fetching just the album's videos plus the
/// total asset count, instead of downloading every asset.
func slideshowDurationMinutes(
    imageCount: Int,
    videos: [AlbumAsset],
    imageInterval: Int
) -> Int {
    var totalSeconds = Double(imageCount * imageInterval)
    for video in videos {
        totalSeconds += Double(video.durationMilliseconds ?? 0) / 1000.0
    }
    return Int((totalSeconds / 60.0).rounded(.up))
}
