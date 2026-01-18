//
//  ContentProvider.swift
//  TopShelf
//
//  Created by Maciej Płoński on 06/01/2026.
//

import ImmichAPI
import TVServices

class ContentProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard
            let albums = try? await ImmichClient.shared.findAlbums(
                order: .fromNewest
            )
        else {
            return nil
        }

        var items: [TVTopShelfSectionedItem] = []
        for album in albums {
            items.append(await generateTopShelfItem(album: album))
        }

        let section = TVTopShelfItemCollection(items: items)
        let content = TVTopShelfSectionedContent(sections: [section])
        return content
    }

    private func generateTopShelfItem(album: AlbumSummary) async
        -> TVTopShelfSectionedItem
    {
        let item = TVTopShelfSectionedItem(identifier: album.id.string)
        item.title = album.albumName.string
        item.imageShape = .hdtv

        var components = URLComponents()
        components.scheme = "bigimmich"
        components.host = "album"
        components.path = "/details"
        components.queryItems = [
            URLQueryItem(name: "albumID", value: album.id.string),
            URLQueryItem(name: "albumName", value: album.albumName.string),
        ]
        if let url = components.url {
            item.displayAction = TVTopShelfAction(url: url)
        }

        let thumbnailUrl = await getThumbnailURL(album: album)
        if let thumbnailUrl {
            item.setImageURL(
                thumbnailUrl,
                for: TVTopShelfItem.ImageTraits.screenScale1x
            )
        }

        return item
    }

    private func getThumbnailURL(album: AlbumSummary) async -> URL? {
        do {
            return try await ImmichAPI.shared.getUrlWithQueryAuth(
                path:
                    "/api/assets/\(album.albumThumbnailAssetId.string)/thumbnail",
                queryParams: ["size": "preview"]
            )
        } catch {
            return nil
        }
    }
}
