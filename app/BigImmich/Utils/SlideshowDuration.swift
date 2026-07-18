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
