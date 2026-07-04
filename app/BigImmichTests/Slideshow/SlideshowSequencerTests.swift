//
//  SlideshowSequencerTests.swift
//  BigImmich
//
//  Created by Maciej Płoński on 18/01/2026.
//

@testable import BigImmich
import ImmichAPI
import Testing
import XCTest

@MainActor
struct SlideshowSequencerSingleAlbumTests {
    private func verifySlideshowAsset(
        asset: SlideshowAsset?,
        albumID: String,
        assetID: String
    ) async throws {
        let unwrapped = try XCTUnwrap(asset)
        XCTAssertEqual(unwrapped.asset.id.string, assetID)
        XCTAssertEqual(unwrapped.album.id.string, albumID)
    }

    @Test func noLoopingGoForwardTillTheEnd() async throws {
        let playlistGetter = FakePlaylistGetter(
            albumPlaylist: Playlist(
                elements: [
                    AlbumSummary.dummy(id: "album.1")
                ],
                looped: false
            ),
            assetsPlaylists: [
                AlbumID(rawValue: "album.1"): Playlist(
                    elements: [
                        AlbumAsset.dummy(id: "asset.1"),
                        AlbumAsset.dummy(id: "asset.2"),
                        AlbumAsset.dummy(id: "asset.3")
                    ],
                    looped: false
                )
            ]
        )

        let slideshow = try await SlideshowSequencer(
            playlistGetter: playlistGetter,
            initialAlbumID: AlbumID(rawValue: "album.1"),
            initialAssetID: nil
        )

        try await verifySlideshowAsset(
            asset: slideshow.current(),
            albumID: "album.1",
            assetID: "asset.1"
        )

        try await verifySlideshowAsset(
            asset: slideshow.next(),
            albumID: "album.1",
            assetID: "asset.2"
        )

        try await verifySlideshowAsset(
            asset: slideshow.next(),
            albumID: "album.1",
            assetID: "asset.3"
        )

        let assetOnceFinished = try await slideshow.next()
        XCTAssertNil(assetOnceFinished)

        try await verifySlideshowAsset(
            asset: slideshow.current(),
            albumID: "album.1",
            assetID: "asset.3"
        )
    }

    @Test func noLoopingGoBackwardsTillTheBeginning() async throws {
        let playlistGetter = FakePlaylistGetter(
            albumPlaylist: Playlist(
                elements: [
                    AlbumSummary.dummy(id: "album.1")
                ],
                looped: false
            ),
            assetsPlaylists: [
                AlbumID(rawValue: "album.1"): Playlist(
                    elements: [
                        AlbumAsset.dummy(id: "asset.1"),
                        AlbumAsset.dummy(id: "asset.2"),
                        AlbumAsset.dummy(id: "asset.3")
                    ],
                    looped: false
                )
            ]
        )

        let slideshow = try await SlideshowSequencer(
            playlistGetter: playlistGetter,
            initialAlbumID: AlbumID(rawValue: "album.1"),
            initialAssetID: AssetID(rawValue: "asset.2")
        )

        try await verifySlideshowAsset(
            asset: slideshow.current(),
            albumID: "album.1",
            assetID: "asset.2"
        )

        try await verifySlideshowAsset(
            asset: slideshow.previous(),
            albumID: "album.1",
            assetID: "asset.1"
        )

        let assetBeforeTheFirstOne = try await slideshow.previous()
        XCTAssertNil(assetBeforeTheFirstOne)

        try await verifySlideshowAsset(
            asset: slideshow.current(),
            albumID: "album.1",
            assetID: "asset.1"
        )
    }

    @Test func loopAlbumIgnoringOtherAlbums() async throws {
        let playlistGetter = FakePlaylistGetter(
            albumPlaylist: Playlist(
                elements: [
                    AlbumSummary.dummy(id: "album.0"),
                    AlbumSummary.dummy(id: "album.1"),
                    AlbumSummary.dummy(id: "album.2")
                ],
                looped: false
            ),
            assetsPlaylists: [
                AlbumID(rawValue: "album.1"): Playlist(
                    elements: [
                        AlbumAsset.dummy(id: "asset.1"),
                        AlbumAsset.dummy(id: "asset.2"),
                        AlbumAsset.dummy(id: "asset.3")
                    ],
                    looped: true
                )
            ]
        )

        let slideshow = try await SlideshowSequencer(
            playlistGetter: playlistGetter,
            initialAlbumID: AlbumID(rawValue: "album.1"),
            initialAssetID: AssetID(rawValue: "asset.3")
        )

        try await verifySlideshowAsset(
            asset: slideshow.current(),
            albumID: "album.1",
            assetID: "asset.3"
        )

        try await verifySlideshowAsset(
            asset: slideshow.next(),
            albumID: "album.1",
            assetID: "asset.1"
        )

        try await verifySlideshowAsset(
            asset: slideshow.previous(),
            albumID: "album.1",
            assetID: "asset.3"
        )
    }
}

@MainActor
struct SlideshowSequencerMultiAlbumTests {
    private func verifySlideshowAsset(
        asset: SlideshowAsset?,
        albumID: String,
        assetID: String
    ) async throws {
        let unwrapped = try XCTUnwrap(asset)
        XCTAssertEqual(unwrapped.asset.id.string, assetID)
        XCTAssertEqual(unwrapped.album.id.string, albumID)
    }

    @Test func noLoopingGoForwardThroughOtherAlbums() async throws {
        let playlistGetter = FakePlaylistGetter(
            albumPlaylist: Playlist(
                elements: [
                    AlbumSummary.dummy(id: "album.1"),
                    AlbumSummary.dummy(id: "album.2")
                ],
                looped: false
            ),
            assetsPlaylists: [
                AlbumID(rawValue: "album.1"): Playlist(
                    elements: [
                        AlbumAsset.dummy(id: "asset.1"),
                        AlbumAsset.dummy(id: "asset.2")
                    ],
                    looped: false
                ),
                AlbumID(rawValue: "album.2"): Playlist(
                    elements: [
                        AlbumAsset.dummy(id: "asset.3"),
                        AlbumAsset.dummy(id: "asset.4")
                    ],
                    looped: false
                )
            ]
        )

        let slideshow = try await SlideshowSequencer(
            playlistGetter: playlistGetter,
            initialAlbumID: AlbumID(rawValue: "album.1"),
            initialAssetID: nil
        )

        try await verifySlideshowAsset(
            asset: slideshow.current(),
            albumID: "album.1",
            assetID: "asset.1"
        )

        try await verifySlideshowAsset(
            asset: slideshow.next(),
            albumID: "album.1",
            assetID: "asset.2"
        )

        try await verifySlideshowAsset(
            asset: slideshow.next(),
            albumID: "album.2",
            assetID: "asset.3"
        )

        try await verifySlideshowAsset(
            asset: slideshow.previous(),
            albumID: "album.1",
            assetID: "asset.2"
        )

        try await verifySlideshowAsset(
            asset: slideshow.next(),
            albumID: "album.2",
            assetID: "asset.3"
        )

        try await verifySlideshowAsset(
            asset: slideshow.next(),
            albumID: "album.2",
            assetID: "asset.4"
        )

        let assetOnceFinished = try await slideshow.next()
        XCTAssertNil(assetOnceFinished)
    }

    @Test func loopAlbumsPlaylist() async throws {
        let playlistGetter = FakePlaylistGetter(
            albumPlaylist: Playlist(
                elements: [
                    AlbumSummary.dummy(id: "album.1"),
                    AlbumSummary.dummy(id: "album.2")
                ],
                looped: true
            ),
            assetsPlaylists: [
                AlbumID(rawValue: "album.1"): Playlist(
                    elements: [
                        AlbumAsset.dummy(id: "asset.1"),
                        AlbumAsset.dummy(id: "asset.2")
                    ],
                    looped: false
                ),
                AlbumID(rawValue: "album.2"): Playlist(
                    elements: [
                        AlbumAsset.dummy(id: "asset.3"),
                        AlbumAsset.dummy(id: "asset.4")
                    ],
                    looped: false
                )
            ]
        )

        let slideshow = try await SlideshowSequencer(
            playlistGetter: playlistGetter,
            initialAlbumID: AlbumID(rawValue: "album.2"),
            initialAssetID: AssetID(rawValue: "asset.4")
        )

        try await verifySlideshowAsset(
            asset: slideshow.current(),
            albumID: "album.2",
            assetID: "asset.4"
        )

        try await verifySlideshowAsset(
            asset: slideshow.next(),
            albumID: "album.1",
            assetID: "asset.1"
        )

        try await verifySlideshowAsset(
            asset: slideshow.previous(),
            albumID: "album.2",
            assetID: "asset.4"
        )
    }

    @Test func loopAssetsAndAlbumsStayInTheOriginalAlbum() async throws {
        let playlistGetter = FakePlaylistGetter(
            albumPlaylist: Playlist(
                elements: [
                    AlbumSummary.dummy(id: "album.0"),
                    AlbumSummary.dummy(id: "album.1"),
                    AlbumSummary.dummy(id: "album.2")
                ],
                looped: true
            ),
            assetsPlaylists: [
                AlbumID(rawValue: "album.1"): Playlist(
                    elements: [
                        AlbumAsset.dummy(id: "asset.1"),
                        AlbumAsset.dummy(id: "asset.2"),
                        AlbumAsset.dummy(id: "asset.3")
                    ],
                    looped: true
                )
            ]
        )

        let slideshow = try await SlideshowSequencer(
            playlistGetter: playlistGetter,
            initialAlbumID: AlbumID(rawValue: "album.1"),
            initialAssetID: AssetID(rawValue: "asset.3")
        )

        try await verifySlideshowAsset(
            asset: slideshow.current(),
            albumID: "album.1",
            assetID: "asset.3"
        )

        try await verifySlideshowAsset(
            asset: slideshow.next(),
            albumID: "album.1",
            assetID: "asset.1"
        )

        try await verifySlideshowAsset(
            asset: slideshow.previous(),
            albumID: "album.1",
            assetID: "asset.3"
        )
    }
}
