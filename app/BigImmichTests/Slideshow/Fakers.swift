//
//  Fakers.swift
//  BigImmich
//
//  Created by Maciej Płoński on 18/01/2026.
//
import ImmichAPI
import Testing
import XCTest

@testable import BigImmich

struct FakePlaylistGetter: SlideshowPlaylistGetterProtocol {
    let albumPlaylist: Playlist<AlbumSummary>
    let assetsPlaylists: [AlbumID: Playlist<AlbumAsset>]

    public init(
        albumPlaylist: Playlist<AlbumSummary>,
        assetsPlaylists: [AlbumID: Playlist<AlbumAsset>]
    ) {
        self.albumPlaylist = albumPlaylist
        self.assetsPlaylists = assetsPlaylists
    }

    func getAlbumsPlaylist(initialAlbumID: AlbumID) async throws -> Playlist<
        AlbumSummary
    > {
        return albumPlaylist
    }

    func getAssetsPlaylist(albumID: AlbumID) async throws -> Playlist<
        AlbumAsset
    > {
        return assetsPlaylists[albumID] ?? Playlist(elements: [], looped: false)
    }
}

extension AlbumAsset {
    static func dummy(id: String) -> AlbumAsset {
        return AlbumAsset(
            id: AssetID(rawValue: id),
            type: "image",
            originalPath: "/path/to/file.jpg",
            duration: "00:00",
            exifInfo: nil,
        )
    }
}

extension AlbumSummary {
    static func dummy(id: String) -> AlbumSummary {
        return AlbumSummary(
            id: AlbumID(rawValue: id),
            albumName: AlbumName(rawValue: "album name"),
            albumThumbnailAssetId: AssetID(rawValue: "asset.id"),
            createdAt: "2025-11-19T19:52:35.661517+00:00",
            updatedAt: "2025-11-19T19:52:39.064032+00:00",
            startDate: "2025-11-06T00:00:00.000Z",
            lastModifiedAssetTimestamp: "2025-11-19T21:07:02.749Z",
        )
    }
}

extension Album {
    static func dummy(id: String, assets: [AlbumAsset]) -> Album {
        return Album(
            id: AlbumID(rawValue: id),
            albumName: AlbumName(rawValue: "album name"),
            albumThumbnailAssetId: AssetID(rawValue: "asset.id"),
            createdAt: "2025-11-19T19:52:35.661517+00:00",
            updatedAt: "2025-11-19T19:52:39.064032+00:00",
            startDate: "2025-11-06T00:00:00.000Z",
            lastModifiedAssetTimestamp: "2025-11-19T21:07:02.749Z",
            assets: assets,
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

    public init(
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

    public init(albumSummaries: [AlbumSummary], albums: [AlbumID: Album]) {
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
