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
    let settings: SlideshowSettings

    public init(settings: SlideshowSettings) {
        self.settings = settings
    }

    public func getAlbumsPlaylist(initialAlbumID: AlbumID) async throws
        -> Playlist<AlbumSummary>
    {
        guard settings.slideshowOnceEndedAction == .loadAnotherAlbum else {
            let albums = try await ImmichClient.shared.findAlbums(
                order: .fromNewest
            )
            let currentAlbum =
                albums.first { $0.id == initialAlbumID } ?? albums[0]
            return Playlist(elements: [currentAlbum], looped: false)
        }

        switch settings.slideshowOnceEndedAnotherAlbumSelection {
        case .older:
            let albums = try await ImmichClient.shared.findAlbums(
                order: .fromNewest
            )
            return Playlist(elements: albums, looped: true)
        case .newer:
            let albums = try await ImmichClient.shared.findAlbums(
                order: .fromOldest
            )
            return Playlist(elements: albums, looped: true)
        case .random:
            let albums = try await ImmichClient.shared.findAlbums(
                order: .fromNewest
            ).shuffled()
            return Playlist(elements: albums, looped: true)
        }
    }

    public func getAssetsPlaylist(albumID: AlbumID) async throws -> Playlist<
        AlbumAsset
    > {
        let loadedAlbum = try await getAlbum(albumID: albumID)

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

    private func getAlbum(albumID: AlbumID) async throws -> Album {
        return try await ImmichAPI.shared.loadObject(
            path: "/api/albums/\(albumID.string)",
            queryParams: [:],
        )
    }
}
