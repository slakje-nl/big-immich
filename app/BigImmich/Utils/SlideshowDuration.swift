import Foundation
import ImmichAPI

func slideshowDurationMinutes(items: [AlbumAsset], imageInterval: Int) -> Int {
    var totalSeconds = 0.0
    for item in items {
        switch item.assetType {
        case .image:
            totalSeconds += Double(imageInterval)
        case .video:
            totalSeconds += Double(item.durationMilliseconds ?? 0) / 1000.0
        case .other:
            break
        }
    }
    return Int((totalSeconds / 60.0).rounded(.up))
}
