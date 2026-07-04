import Foundation
import ImmichAPI

func slideshowDurationMinutes(items: [AlbumAsset], imageInterval: Int) -> Int {
    var totalSeconds = 0.0
    for item in items {
        switch item.assetType {
        case .image:
            totalSeconds += Double(imageInterval)
        case .video:
            totalSeconds += videoDurationSeconds(item.duration)
        case .other:
            break
        }
    }
    return Int((totalSeconds / 60.0).rounded(.up))
}

private func videoDurationSeconds(_ duration: String) -> Double {
    let components = duration.split(separator: ":")
    guard components.count == 3,
          let hours = Double(components[0]),
          let minutes = Double(components[1]),
          let seconds = Double(components[2])
    else { return 0 }

    return hours * 3600 + minutes * 60 + seconds
}
