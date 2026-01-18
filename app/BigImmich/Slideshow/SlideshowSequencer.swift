//
//  Slideshow.swift
//  BigImmich
//
//  Created by Maciej Płoński on 16/01/2026.
//

import ImmichAPI

struct SlideshowCounter {
    let current: Int
    let total: Int
}

struct SlideshowAsset {
    let album: AlbumSummary
    let asset: AlbumAsset
    let counter: SlideshowCounter
}

class SlideshowSequencer {
    let playlistGetter: SlideshowPlaylistGetterProtocol

    var albumPlaylist: Playlist<AlbumSummary>
    var albumIndex: Int = 0

    var assetsPlaylist: MemoryCache<AlbumID, Playlist<AlbumAsset>>
    var assetIndex: Int = 0

    public init(
        playlistGetter: SlideshowPlaylistGetterProtocol,
        initialAlbumID: AlbumID,
        initialAssetID: AssetID?
    ) async throws {
        self.playlistGetter = playlistGetter

        self.assetsPlaylist = MemoryCache(countLimit: 10)

        albumPlaylist = try await self.playlistGetter.getAlbumsPlaylist(
            initialAlbumID: initialAlbumID
        )
        albumIndex =
            albumPlaylist.elements.firstIndex { $0.id == initialAlbumID } ?? 0

        let assetsPlaylist = try await getAssetsPlaylist(
            albumID: initialAlbumID
        )
        assetIndex =
            assetsPlaylist.elements.firstIndex { $0.id == initialAssetID } ?? 0
    }

    private func getAssetsPlaylist(albumID: AlbumID) async throws
        -> Playlist<AlbumAsset>
    {
        if let cached = assetsPlaylist.get(albumID) { return cached }

        let playlist = try await playlistGetter.getAssetsPlaylist(
            albumID: albumID
        )

        assetsPlaylist.set(albumID, value: playlist)
        return playlist
    }

    private func getNextAssetIndex() async throws -> (Int, Int)? {
        let album = albumPlaylist.elements[albumIndex]
        let assetsPlaylist = try await getAssetsPlaylist(albumID: album.id)

        if assetIndex < assetsPlaylist.elements.count - 1 {
            return (albumIndex, assetIndex + 1)
        }

        if assetsPlaylist.looped {
            return (albumIndex, 0)
        }

        if albumIndex < albumPlaylist.elements.count - 1 {
            return (albumIndex + 1, 0)
        }

        if albumPlaylist.looped {
            return (0, 0)
        }

        return nil
    }

    private func getPreviousAssetIndex() async throws -> (Int, Int)? {
        let album = albumPlaylist.elements[albumIndex]
        let assetsPlaylist = try await getAssetsPlaylist(albumID: album.id)

        if assetIndex > 0 {
            return (albumIndex, assetIndex - 1)
        }

        if assetsPlaylist.looped {
            return (albumIndex, assetsPlaylist.elements.count - 1)
        }

        if albumIndex > 0 {
            let previousAlbum = albumPlaylist.elements[albumIndex - 1]
            let previousAssets = try await getAssetsPlaylist(
                albumID: previousAlbum.id
            )

            return (albumIndex - 1, previousAssets.elements.count - 1)
        }

        if albumPlaylist.looped {
            let previousAlbum = albumPlaylist.elements[
                albumPlaylist.elements.count - 1
            ]
            let previousAssets = try await getAssetsPlaylist(
                albumID: previousAlbum.id
            )

            return (
                albumPlaylist.elements.count - 1,
                previousAssets.elements.count - 1
            )
        }

        return nil
    }

    private func getSlideshowAsset(albumIndex: Int, assetIndex: Int)
        async throws -> SlideshowAsset?
    {
        let album = albumPlaylist.elements[albumIndex]
        let assetsPlaylist = try await getAssetsPlaylist(albumID: album.id)

        return SlideshowAsset(
            album: album,
            asset: assetsPlaylist.elements[assetIndex],
            counter: SlideshowCounter(
                current: assetIndex + 1,
                total: assetsPlaylist.elements.count
            ),
        )
    }

    public func previous() async throws -> SlideshowAsset? {
        if let (nextAlbumIndex, nextAssetIndex) =
            try await getPreviousAssetIndex()
        {
            albumIndex = nextAlbumIndex
            assetIndex = nextAssetIndex
            return try await getSlideshowAsset(
                albumIndex: nextAlbumIndex,
                assetIndex: nextAssetIndex
            )
        }
        return nil
    }

    public func previewPrevious() async throws -> SlideshowAsset? {
        if let (nextAlbumIndex, nextAssetIndex) =
            try await getPreviousAssetIndex()
        {
            return try await getSlideshowAsset(
                albumIndex: nextAlbumIndex,
                assetIndex: nextAssetIndex
            )
        }
        return nil
    }

    public func next() async throws -> SlideshowAsset? {
        if let (nextAlbumIndex, nextAssetIndex) = try await getNextAssetIndex()
        {
            albumIndex = nextAlbumIndex
            assetIndex = nextAssetIndex
            return try await getSlideshowAsset(
                albumIndex: nextAlbumIndex,
                assetIndex: nextAssetIndex
            )
        }
        return nil
    }

    public func previewNext() async throws -> SlideshowAsset? {
        if let (nextAlbumIndex, nextAssetIndex) = try await getNextAssetIndex()
        {
            return try await getSlideshowAsset(
                albumIndex: nextAlbumIndex,
                assetIndex: nextAssetIndex
            )
        }
        return nil
    }

    public func current() async throws -> SlideshowAsset? {
        return try await getSlideshowAsset(
            albumIndex: albumIndex,
            assetIndex: assetIndex
        )
    }
}
