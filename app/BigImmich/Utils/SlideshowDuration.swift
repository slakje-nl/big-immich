import Foundation
import ImmichAPI

/// Total slideshow runtime, in minutes rounded up.
///
/// Images all play for the fixed `imageInterval`, so only their count is needed —
/// never their metadata. Videos play for their own length, passed as a summed total
/// so the inputs can be cached without keeping the asset list around.
func slideshowDurationMinutes(
    imageCount: Int,
    videoDurationMilliseconds: Int,
    imageInterval: Int
) -> Int {
    let totalSeconds = Double(imageCount * imageInterval)
        + Double(videoDurationMilliseconds) / 1000.0
    return Int((totalSeconds / 60.0).rounded(.up))
}

/// Number of still images in an album, derived from its total asset count and the known
/// video count. Returns `nil` when the total isn't known (e.g. an older server that omits
/// `assetCount`), so callers can avoid falsely claiming "0 images". Any non-image/non-video
/// assets fold into the image count, which is close enough for the details summary.
func albumImageCount(assetCount: Int?, videoCount: Int) -> Int? {
    guard let assetCount else { return nil }
    return max(assetCount - videoCount, 0)
}
