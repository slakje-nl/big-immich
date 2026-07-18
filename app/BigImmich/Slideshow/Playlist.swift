//
//  Playlist.swift
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

    init(
        settings: SlideshowSettingsProtocol,
        immichClient: ImmichClientProtocol
    ) {
        self.settings = settings
        self.immichClient = immichClient
    }

    func getAlbumsPlaylist(initialAlbumID: AlbumID) async throws
        -> Playlist<AlbumSummary>
    {
        guard settings.slideshowOnceEndedAction == .loadAnotherAlbum else {
            let albums = try await immichClient.findAlbums(order: .fromNewest)
            guard let currentAlbum = albums.first(where: { $0.id == initialAlbumID }) ?? albums.first else {
                return Playlist(elements: [], looped: false)
            }
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

    func getAssetsPlaylist(albumID: AlbumID) async throws -> Playlist<
        AlbumAsset
    > {
        let loadedAssets = try await albumAssets(albumID: albumID)

        let looped = switch settings.slideshowOnceEndedAction {
        case .stopAndNotify:
            false
        case .startAgain:
            true
        case .loadAnotherAlbum:
            false
        }

        let assets: [AlbumAsset] = switch settings.slideshowDirection {
        case .oldestToNewest:
            loadedAssets.reversed()
        case .newestToOldest:
            loadedAssets
        case .randomized:
            loadedAssets.shuffled()
        }

        return Playlist(elements: assets, looped: looped)
    }

    /// Album assets, served from the disk cache when present for a fast slideshow start; the
    /// fresh list is fetched and cached in the background, so newly added assets converge on
    /// the next slideshow. On a cache miss we fetch synchronously and cache the result.
    private func albumAssets(albumID: AlbumID) async throws -> [AlbumAsset] {
        if let cached = AlbumAssetsCache.shared.cached(albumID: albumID) {
            Task { await refreshAssetsCache(albumID: albumID) }
            return cached
        }
        let assets = try await immichClient.getAlbumAssets(albumID: albumID)
        AlbumAssetsCache.shared.set(albumID: albumID, assets: assets)
        return assets
    }

    private func refreshAssetsCache(albumID: AlbumID) async {
        guard let assets = try? await immichClient.getAlbumAssets(albumID: albumID) else { return }
        AlbumAssetsCache.shared.set(albumID: albumID, assets: assets)
    }
}
