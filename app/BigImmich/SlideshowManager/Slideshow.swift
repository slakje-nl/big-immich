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
    let album: Album
    let asset: AlbumAsset
    let counter: SlideshowCounter
}

class Slideshow {
    let slideshowDirection: SlideshowDirection
    let slideshowOnceEndedAction: SlideshowOnceEndedAction

    var album: Album? = nil
    var assets: [AlbumAsset] = []
    var assetIndex: Int = 0

    public init(
        slideshowDirection: SlideshowDirection,
        slideshowOnceEndedAction: SlideshowOnceEndedAction
    ) {
        self.slideshowDirection = slideshowDirection
        self.slideshowOnceEndedAction = slideshowOnceEndedAction
    }

    public func load(albumID: AlbumID, initialAssetID: AssetID?) async throws {
        let loadedAlbum = try await getAlbum(albumID: albumID)
        album = loadedAlbum

        switch slideshowDirection {
        case .oldestToNewest:
            assets = loadedAlbum.assets.reversed()
        case .newestToOldest:
            assets = loadedAlbum.assets
        case .randomized:
            assets = loadedAlbum.assets.shuffled()
        }
        assetIndex = assets.firstIndex { $0.id == initialAssetID } ?? 0
    }

    private func getNextAssetIndex() -> Int? {
        guard let album else { return nil }

        if assetIndex < album.assets.count - 1 {
            return assetIndex + 1
        }

        switch slideshowOnceEndedAction {
        case .stopAndNotify:
            return nil
        case .startAgain:
            return 0
        case .loadAnotherAlbum:
            return nil  // "TODO"
        }
    }

    private func getPreviousAssetIndex() -> Int? {
        guard let album else { return nil }

        if assetIndex > 0 {
            return assetIndex - 1
        }

        switch slideshowOnceEndedAction {
        case .stopAndNotify:
            return nil
        case .startAgain:
            return album.assets.count - 1
        case .loadAnotherAlbum:
            return nil  // "TODO"
        }
    }

    private func getSlideshowAsset(index: Int) -> SlideshowAsset? {
        guard let album else { return nil }

        return SlideshowAsset(
            album: album,
            asset: assets[index],
            counter: SlideshowCounter(current: index + 1, total: assets.count),
        )
    }

    public func previous() -> SlideshowAsset? {
        if let previousIndex = getPreviousAssetIndex() {
            assetIndex = previousIndex
            return getSlideshowAsset(index: assetIndex)
        }
        return nil
    }

    public func previewPrevious() -> SlideshowAsset? {
        if let previousIndex = getPreviousAssetIndex() {
            return getSlideshowAsset(index: previousIndex)
        }
        return nil
    }

    public func next() -> SlideshowAsset? {
        if let nextIndex = getNextAssetIndex() {
            assetIndex = nextIndex
            return getSlideshowAsset(index: assetIndex)
        }
        return nil
    }

    public func previewNext() -> SlideshowAsset? {
        if let nextIndex = getNextAssetIndex() {
            return getSlideshowAsset(index: nextIndex)
        }
        return nil
    }

    public func current() -> SlideshowAsset? {
        return getSlideshowAsset(index: assetIndex)
    }

    private func getAlbum(albumID: AlbumID) async throws -> Album {
        return try await ImmichAPI.shared.loadObject(
            path: "/api/albums/\(albumID.string)",
            queryParams: [:],
        )
    }
}
