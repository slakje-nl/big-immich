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

class Slideshow {
    let slideshowDirection: SlideshowDirection
    let slideshowOnceEndedAction: SlideshowOnceEndedAction
    var slideshowOnceEndedAnotherAlbumSelection:
        SlideshowOnceEndedAnotherAlbumSelection

    var albumPlaylist: [AlbumSummary] = []
    var albumIndex: Int = 0

    var assetsPlaylist: MemoryCache<AlbumID, [AlbumAsset]>
    var assetIndex: Int = 0

    public init(
        slideshowDirection: SlideshowDirection,
        slideshowOnceEndedAction: SlideshowOnceEndedAction,
        slideshowOnceEndedAnotherAlbumSelection:
            SlideshowOnceEndedAnotherAlbumSelection,
    ) {
        self.slideshowDirection = slideshowDirection
        self.slideshowOnceEndedAction = slideshowOnceEndedAction
        self.slideshowOnceEndedAnotherAlbumSelection =
            slideshowOnceEndedAnotherAlbumSelection
        self.assetsPlaylist = MemoryCache(countLimit: 10)
    }

    public func load(initialAlbumID: AlbumID, initialAssetID: AssetID?)
        async throws
    {
        try await loadAlbumsPlaylist(initialAlbumID: initialAlbumID)
        try await loadAssetsPlaylist(
            initialAlbumID: initialAlbumID,
            initialAssetID: initialAssetID
        )
    }

    private func loadAlbumsPlaylist(initialAlbumID: AlbumID) async throws {
        switch slideshowOnceEndedAnotherAlbumSelection {
        case .older:
            albumPlaylist = try await ImmichClient.shared.findAlbums(
                order: .fromNewest
            )
        case .newer:
            albumPlaylist = try await ImmichClient.shared.findAlbums(
                order: .fromOldest
            )
        case .random:
            let allAlbums = try await ImmichClient.shared.findAlbums(
                order: .fromNewest
            )
            albumPlaylist = allAlbums.shuffled()
        }

        albumIndex = albumPlaylist.firstIndex { $0.id == initialAlbumID } ?? 0
    }

    private func loadAssetsPlaylist(
        initialAlbumID: AlbumID,
        initialAssetID: AssetID?
    ) async throws {
        let playlist = try await getAssetsPlaylist(albumID: initialAlbumID)
        assetIndex = playlist.firstIndex { $0.id == initialAssetID } ?? 0
    }

    private func getAssetsPlaylist(albumID: AlbumID) async throws
        -> [AlbumAsset]
    {
        if let cached = assetsPlaylist.get(albumID) {
            return cached
        }

        let loadedAlbum = try await getAlbum(albumID: albumID)

        var assets: [AlbumAsset]
        switch slideshowDirection {
        case .oldestToNewest:
            assets = loadedAlbum.assets.reversed()
        case .newestToOldest:
            assets = loadedAlbum.assets
        case .randomized:
            assets = loadedAlbum.assets.shuffled()
        }
        assetsPlaylist.set(albumID, value: assets)
        return assets
    }

    private func getNextAssetIndex() async throws -> (Int, Int)? {
        let album = albumPlaylist[albumIndex]
        let assets = try await getAssetsPlaylist(albumID: album.id)

        if assetIndex < assets.count - 1 {
            return (albumIndex, assetIndex + 1)
        }

        switch slideshowOnceEndedAction {
        case .stopAndNotify:
            return nil
        case .startAgain:
            return (albumIndex, 0)
        case .loadAnotherAlbum:
            if albumIndex < albumPlaylist.count - 1 {
                return (albumIndex + 1, 0)
            } else {
                return (0, 0)
            }
        }
    }

    private func getPreviousAssetIndex() async throws -> (Int, Int)? {
        let album = albumPlaylist[albumIndex]
        let assets = try await getAssetsPlaylist(albumID: album.id)

        if assetIndex > 0 {
            return (albumIndex, assetIndex - 1)
        }

        switch slideshowOnceEndedAction {
        case .stopAndNotify:
            return nil
        case .startAgain:
            return (albumIndex, assets.count - 1)
        case .loadAnotherAlbum:
            let previousAlbumIndex =
                albumIndex > 0 ? albumIndex - 1 : albumPlaylist.count - 1
            let previousAlbum = albumPlaylist[previousAlbumIndex]
            let previousAssets = try await getAssetsPlaylist(
                albumID: previousAlbum.id
            )

            return (previousAlbumIndex, previousAssets.count - 1)
        }
    }

    private func getSlideshowAsset(albumIndex: Int, assetIndex: Int)
        async throws -> SlideshowAsset?
    {
        let album = albumPlaylist[albumIndex]
        let assets = try await getAssetsPlaylist(albumID: album.id)

        return SlideshowAsset(
            album: album,
            asset: assets[assetIndex],
            counter: SlideshowCounter(
                current: assetIndex + 1,
                total: assets.count
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

    private func getAlbum(albumID: AlbumID) async throws -> Album {
        return try await ImmichAPI.shared.loadObject(
            path: "/api/albums/\(albumID.string)",
            queryParams: [:],
        )
    }
}
