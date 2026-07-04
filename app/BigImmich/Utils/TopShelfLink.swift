import Foundation
import ImmichAPI

struct TopShelfAlbumLink: Equatable {
    let albumID: AlbumID
    let albumName: AlbumName
}

func parseTopShelfAlbumLink(_ url: URL) -> TopShelfAlbumLink? {
    guard url.scheme == "bigimmich", url.host == "album" else { return nil }

    let pathComponents = url.pathComponents.filter { $0 != "/" }
    guard pathComponents.first == "details" else { return nil }

    let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    guard let id = queryItems.first(where: { $0.name == "albumID" })?.value,
          let name = queryItems.first(where: { $0.name == "albumName" })?.value
    else { return nil }

    return TopShelfAlbumLink(
        albumID: AlbumID(rawValue: id),
        albumName: AlbumName(rawValue: name)
    )
}
