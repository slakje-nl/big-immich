//
//  SlideshowSequencer.swift
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

actor SlideshowSequencer {
    private let playlistGetter: SlideshowPlaylistGetterProtocol

    private let albumPlaylist: Playlist<AlbumSummary>
    private var albumIndex = 0

    private var assetsPlaylists: [AlbumID: Playlist<AlbumAsset>] = [:]
    private var assetIndex = 0

    init(
        playlistGetter: SlideshowPlaylistGetterProtocol,
        initialAlbumID: AlbumID,
        initialAssetID: AssetID?
    ) async throws {
        self.playlistGetter = playlistGetter
        albumPlaylist = try await playlistGetter.getAlbumsPlaylist(
            initialAlbumID: initialAlbumID
        )
        albumIndex = albumPlaylist.elements.firstIndex { $0.id == initialAlbumID } ?? 0

        try await positionAtStart(initialAssetID: initialAssetID)
    }

    private func positionAtStart(initialAssetID: AssetID?) async throws {
        guard !albumPlaylist.elements.isEmpty else { return }

        if try await assetCount(atAlbum: albumIndex) == 0 {
            albumIndex = try await firstNonEmptyAlbumIndex() ?? albumIndex
            assetIndex = 0
            return
        }

        guard let initialAssetID else {
            assetIndex = 0
            return
        }
        let assets = try await assetsPlaylist(atAlbum: albumIndex)
        assetIndex = assets.elements.firstIndex { $0.id == initialAssetID } ?? 0
    }

    private func assetsPlaylist(albumID: AlbumID) async throws -> Playlist<AlbumAsset> {
        if let cached = assetsPlaylists[albumID] { return cached }

        let playlist = try await playlistGetter.getAssetsPlaylist(albumID: albumID)
        assetsPlaylists[albumID] = playlist
        return playlist
    }

    private func assetsPlaylist(atAlbum index: Int) async throws -> Playlist<AlbumAsset> {
        try await assetsPlaylist(albumID: albumPlaylist.elements[index].id)
    }

    private func assetCount(atAlbum index: Int) async throws -> Int {
        guard albumPlaylist.elements.indices.contains(index) else { return 0 }
        return try await assetsPlaylist(atAlbum: index).elements.count
    }

    private func firstNonEmptyAlbumIndex() async throws -> Int? {
        for index in albumPlaylist.elements.indices {
            if try await assetCount(atAlbum: index) > 0 { return index }
        }
        return nil
    }

    private func nextNonEmptyAlbumIndex(after index: Int) async throws -> Int? {
        let count = albumPlaylist.elements.count
        guard count > 0 else { return nil }

        for offset in 1 ... count {
            let raw = index + offset
            let candidate = albumPlaylist.looped ? raw % count : raw
            if candidate >= count { break }
            if try await assetCount(atAlbum: candidate) > 0 { return candidate }
        }
        return nil
    }

    private func previousNonEmptyAlbumIndex(before index: Int) async throws -> Int? {
        let count = albumPlaylist.elements.count
        guard count > 0 else { return nil }

        for offset in 1 ... count {
            let raw = index - offset
            let candidate = albumPlaylist.looped ? (raw % count + count) % count : raw
            if candidate < 0 { break }
            if try await assetCount(atAlbum: candidate) > 0 { return candidate }
        }
        return nil
    }

    private func getNextAssetIndex() async throws -> (Int, Int)? {
        guard albumPlaylist.elements.indices.contains(albumIndex) else { return nil }
        let assets = try await assetsPlaylist(atAlbum: albumIndex)

        if assetIndex + 1 < assets.elements.count {
            return (albumIndex, assetIndex + 1)
        }
        if assets.looped, !assets.elements.isEmpty {
            return (albumIndex, 0)
        }
        if let nextAlbum = try await nextNonEmptyAlbumIndex(after: albumIndex) {
            return (nextAlbum, 0)
        }
        return nil
    }

    private func getPreviousAssetIndex() async throws -> (Int, Int)? {
        guard albumPlaylist.elements.indices.contains(albumIndex) else { return nil }
        let assets = try await assetsPlaylist(atAlbum: albumIndex)

        if assetIndex > 0 {
            return (albumIndex, assetIndex - 1)
        }
        if assets.looped, !assets.elements.isEmpty {
            return (albumIndex, assets.elements.count - 1)
        }
        if let previousAlbum = try await previousNonEmptyAlbumIndex(before: albumIndex) {
            let count = try await assetCount(atAlbum: previousAlbum)
            return (previousAlbum, count - 1)
        }
        return nil
    }

    private func getSlideshowAsset(albumIndex: Int, assetIndex: Int) async throws -> SlideshowAsset? {
        guard albumPlaylist.elements.indices.contains(albumIndex) else { return nil }
        let album = albumPlaylist.elements[albumIndex]

        let assets = try await assetsPlaylist(albumID: album.id)
        guard assets.elements.indices.contains(assetIndex) else { return nil }

        return SlideshowAsset(
            album: album,
            asset: assets.elements[assetIndex],
            counter: SlideshowCounter(
                current: assetIndex + 1,
                total: assets.elements.count
            )
        )
    }

    func previous() async throws -> SlideshowAsset? {
        guard let (albumIndex, assetIndex) = try await getPreviousAssetIndex() else {
            return nil
        }
        self.albumIndex = albumIndex
        self.assetIndex = assetIndex
        return try await getSlideshowAsset(albumIndex: albumIndex, assetIndex: assetIndex)
    }

    func previewPrevious() async throws -> SlideshowAsset? {
        guard let (albumIndex, assetIndex) = try await getPreviousAssetIndex() else {
            return nil
        }
        return try await getSlideshowAsset(albumIndex: albumIndex, assetIndex: assetIndex)
    }

    func next() async throws -> SlideshowAsset? {
        guard let (albumIndex, assetIndex) = try await getNextAssetIndex() else {
            return nil
        }
        self.albumIndex = albumIndex
        self.assetIndex = assetIndex
        return try await getSlideshowAsset(albumIndex: albumIndex, assetIndex: assetIndex)
    }

    func previewNext() async throws -> SlideshowAsset? {
        guard let (albumIndex, assetIndex) = try await getNextAssetIndex() else {
            return nil
        }
        return try await getSlideshowAsset(albumIndex: albumIndex, assetIndex: assetIndex)
    }

    func current() async throws -> SlideshowAsset? {
        try await getSlideshowAsset(albumIndex: albumIndex, assetIndex: assetIndex)
    }
}
