//
//  Slideshow.swift
//  BigImmich
//
//  Created by Maciej Płoński on 16/01/2026.
//

import ImmichAPI

struct Playlist<T> {
    let elements: [T]
    let looped: Bool
}

protocol SlideshowPlaylistGetterProtocol {
    func getAlbumsPlaylist(initialAlbumID: AlbumID) async throws -> Playlist<
        AlbumSummary
    >
    func getAssetsPlaylist(albumID: AlbumID) async throws -> Playlist<
        AlbumAsset
    >
}

class SlideshowPlaylistGetter: SlideshowPlaylistGetterProtocol {
    let settings: SlideshowSettingsProtocol
    let immichClient: ImmichClientProtocol

    public init(
        settings: SlideshowSettingsProtocol,
        immichClient: ImmichClientProtocol
    ) {
        self.settings = settings
        self.immichClient = immichClient
    }

    public func getAlbumsPlaylist(initialAlbumID: AlbumID) async throws
        -> Playlist<AlbumSummary>
    {
        guard settings.slideshowOnceEndedAction == .loadAnotherAlbum else {
            let albums = try await immichClient.findAlbums(order: .fromNewest)
            let currentAlbum =
                albums.first { $0.id == initialAlbumID } ?? albums[0]
            return Playlist(elements: [currentAlbum], looped: false)
        }

        switch settings.slideshowOnceEndedAnotherAlbumSelection {
        case .older:
            let albums = try await immichClient.findAlbums(order: .fromNewest)
            return Playlist(elements: albums, looped: true)
        case .newer:
            let albums = try await immichClient.findAlbums(order: .fromOldest)
            return Playlist(elements: albums, looped: true)
        case .random:
            let albums = try await immichClient.findAlbums(order: .fromNewest)
                .shuffled()
            return Playlist(elements: albums, looped: true)
        }
    }

    public func getAssetsPlaylist(albumID: AlbumID) async throws -> Playlist<
        AlbumAsset
    > {
        let loadedAlbum = try await immichClient.getAlbum(albumID: albumID)

        var looped: Bool
        switch settings.slideshowOnceEndedAction {
        case .stopAndNotify:
            looped = false
        case .startAgain:
            looped = true
        case .loadAnotherAlbum:
            looped = false
        }

        var assets: [AlbumAsset]
        switch settings.slideshowDirection {
        case .oldestToNewest:
            assets = loadedAlbum.assets.reversed()
        case .newestToOldest:
            assets = loadedAlbum.assets
        case .randomized:
            assets = loadedAlbum.assets.shuffled()
        }

        return Playlist(elements: assets, looped: looped)
    }
}
