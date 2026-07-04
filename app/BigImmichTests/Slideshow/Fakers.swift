//
//  Fakers.swift
//  BigImmich
//
//  Created by Maciej Płoński on 18/01/2026.
//
@testable import BigImmich
import ImmichAPI
import Testing
import XCTest

struct FakePlaylistGetter: SlideshowPlaylistGetterProtocol {
    let albumPlaylist: Playlist<AlbumSummary>
    let assetsPlaylists: [AlbumID: Playlist<AlbumAsset>]

    func getAlbumsPlaylist(initialAlbumID _: AlbumID) async throws -> Playlist<
        AlbumSummary
    > {
        albumPlaylist
    }

    func getAssetsPlaylist(albumID: AlbumID) async throws -> Playlist<
        AlbumAsset
    > {
        assetsPlaylists[albumID] ?? Playlist(elements: [], looped: false)
    }
}

extension AlbumAsset {
    static func dummy(id: String) -> AlbumAsset {
        AlbumAsset(
            id: AssetID(rawValue: id),
            type: "image",
            originalPath: "/path/to/file.jpg",
            duration: "00:00",
            exifInfo: nil
        )
    }
}

extension AlbumSummary {
    static func dummy(id: String) -> AlbumSummary {
        AlbumSummary(
            id: AlbumID(rawValue: id),
            albumName: AlbumName(rawValue: "album name"),
            albumThumbnailAssetId: AssetID(rawValue: "asset.id"),
            createdAt: "2025-11-19T19:52:35.661517+00:00",
            updatedAt: "2025-11-19T19:52:39.064032+00:00",
            startDate: "2025-11-06T00:00:00.000Z",
            lastModifiedAssetTimestamp: "2025-11-19T21:07:02.749Z"
        )
    }
}

extension Album {
    static func dummy(id: String, assets: [AlbumAsset]) -> Album {
        Album(
            id: AlbumID(rawValue: id),
            albumName: AlbumName(rawValue: "album name"),
            albumThumbnailAssetId: AssetID(rawValue: "asset.id"),
            createdAt: "2025-11-19T19:52:35.661517+00:00",
            updatedAt: "2025-11-19T19:52:39.064032+00:00",
            startDate: "2025-11-06T00:00:00.000Z",
            lastModifiedAssetTimestamp: "2025-11-19T21:07:02.749Z",
            assets: assets
        )
    }
}

struct FakeSettings: SlideshowSettingsProtocol {
    var slideshowInterval: Int = 5
    var slideshowDirection: SlideshowDirection
    var slideshowLeftAction: SlideshowAction = .goToNext
    var slideshowRightAction: SlideshowAction = .goToPrevious
    var slideshowOnceEndedAction: SlideshowOnceEndedAction
    var slideshowOnceEndedAnotherAlbumSelection:
        SlideshowOnceEndedAnotherAlbumSelection
    var slideshowShowProgressBar: SlideshowShowProgressBar = .always

    init(
        slideshowOnceEndedAction: SlideshowOnceEndedAction,
        slideshowOnceEndedAnotherAlbumSelection:
        SlideshowOnceEndedAnotherAlbumSelection,
        slideshowDirection: SlideshowDirection
    ) {
        self.slideshowOnceEndedAction = slideshowOnceEndedAction
        self.slideshowOnceEndedAnotherAlbumSelection =
            slideshowOnceEndedAnotherAlbumSelection
        self.slideshowDirection = slideshowDirection
    }
}

class FakeImmichClient: ImmichClientProtocol {
    let albumSummaries: [AlbumSummary]
    let albums: [AlbumID: Album]

    var lastAlbumsOrder: AlbumsOrder = .fromOldest

    init(albumSummaries: [AlbumSummary], albums: [AlbumID: Album]) {
        self.albumSummaries = albumSummaries
        self.albums = albums
    }

    func findAlbums(order: AlbumsOrder) async throws -> [AlbumSummary] {
        lastAlbumsOrder = order

        return albumSummaries
    }

    func getAlbum(albumID: AlbumID) async throws -> Album {
        if let exists = albums[albumID] {
            return exists
        }
        return Album.dummy(id: "dummy", assets: [])
    }
}
