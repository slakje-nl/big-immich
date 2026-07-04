import Foundation
import ImmichAPI

func formattedCaptureDate(_ asset: AlbumAsset) -> String {
    guard let original = asset.exifInfo?.dateTimeOriginal else { return "" }

    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = parser.date(from: original) else { return "" }

    let output = DateFormatter()
    output.dateFormat = "dd/MM/yyyy HH:mm"
    return output.string(from: date)
}

func formattedLocation(_ asset: AlbumAsset) -> String {
    guard let exif = asset.exifInfo,
          let city = exif.city,
          let state = exif.state,
          let country = exif.country
    else { return "" }

    return "\(city), \(state), \(country)"
}
