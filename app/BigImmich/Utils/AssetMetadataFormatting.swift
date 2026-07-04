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
    guard let exif = asset.exifInfo else { return "" }

    return [exif.city, exif.state, exif.country]
        .compactMap(\.self)
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
}
