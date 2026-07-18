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
            durationMilliseconds: nil,
            exifInfo: nil
        )
    }
}

extension AlbumSummary {
    static func dummy(id: String, assetCount: Int? = nil) -> AlbumSummary {
        AlbumSummary(
            id: AlbumID(rawValue: id),
            albumName: AlbumName(rawValue: "album name"),
            albumThumbnailAssetId: AssetID(rawValue: "asset.id"),
            startDate: "2025-11-06T00:00:00.000Z",
            assetCount: assetCount
        )
    }
}

extension Album {
    static func dummy(id: String) -> Album {
        Album(
            id: AlbumID(rawValue: id),
            albumName: AlbumName(rawValue: "album name"),
            albumThumbnailAssetId: AssetID(rawValue: "asset.id")
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
    var slideshowImageQuality: SlideshowImageQuality = .fullsize
    var slideshowPreloadVideos: Bool = true

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
    let albumAssets: [AlbumID: [AlbumAsset]]

    var lastAlbumsOrder: AlbumsOrder = .fromOldest

    init(albumSummaries: [AlbumSummary], albumAssets: [AlbumID: [AlbumAsset]]) {
        self.albumSummaries = albumSummaries
        self.albumAssets = albumAssets
    }

    func findAlbums(order: AlbumsOrder) async throws -> [AlbumSummary] {
        lastAlbumsOrder = order

        return albumSummaries
    }

    func getAlbum(albumID: AlbumID) async throws -> Album {
        Album.dummy(id: albumID.string)
    }

    func getAlbumAssets(albumID: AlbumID) async throws -> [AlbumAsset] {
        albumAssets[albumID] ?? []
    }

    func getServerVersion() async throws -> ServerVersion {
        ServerVersion(major: 3, minor: 0, patch: 2)
    }

    func getAsset(assetID: AssetID) async throws -> AlbumAsset {
        AlbumAsset.dummy(id: assetID.string)
    }

    func loadThumbnail(
        assetID _: AssetID,
        size _: ThumbnailSize,
        retries _: Int
    ) async throws -> Data {
        Data()
    }

    func thumbnailURL(assetID: AssetID, size _: ThumbnailSize) async throws -> URL {
        URL(string: "https://example.test/\(assetID.string)")!
    }

    func videoPlaybackURL(assetID: AssetID) async throws -> URL {
        URL(string: "https://example.test/\(assetID.string)/video")!
    }
}
