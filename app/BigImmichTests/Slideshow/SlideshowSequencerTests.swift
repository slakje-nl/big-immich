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
struct SlideshowSequencerEdgeCaseTests {
    private func singleAlbumGetter() -> FakePlaylistGetter {
        FakePlaylistGetter(
            albumPlaylist: Playlist(
                elements: [AlbumSummary.dummy(id: "album.1")],
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
    }

    @Test func unknownInitialAssetStartsAtFirst() async throws {
        let slideshow = try await SlideshowSequencer(
            playlistGetter: singleAlbumGetter(),
            initialAlbumID: AlbumID(rawValue: "album.1"),
            initialAssetID: AssetID(rawValue: "does-not-exist")
        )

        let current = try #require(await slideshow.current())
        #expect(current.asset.id.string == "asset.1")
    }

    @Test func counterReflectsPositionAndTotal() async throws {
        let slideshow = try await SlideshowSequencer(
            playlistGetter: singleAlbumGetter(),
            initialAlbumID: AlbumID(rawValue: "album.1"),
            initialAssetID: nil
        )

        let first = try #require(await slideshow.current())
        #expect(first.counter.current == 1)
        #expect(first.counter.total == 3)

        let second = try #require(await slideshow.next())
        #expect(second.counter.current == 2)
        #expect(second.counter.total == 3)
    }

    @Test func previewDoesNotAdvancePosition() async throws {
        let slideshow = try await SlideshowSequencer(
            playlistGetter: singleAlbumGetter(),
            initialAlbumID: AlbumID(rawValue: "album.1"),
            initialAssetID: nil
        )

        let previewedNext = try #require(await slideshow.previewNext())
        #expect(previewedNext.asset.id.string == "asset.2")

        let previewedAgain = try #require(await slideshow.previewNext())
        #expect(previewedAgain.asset.id.string == "asset.2")

        let current = try #require(await slideshow.current())
        #expect(current.asset.id.string == "asset.1")
    }

    @Test func emptyAlbumInChainIsSkippedGoingForward() async throws {
        let playlistGetter = FakePlaylistGetter(
            albumPlaylist: Playlist(
                elements: [
                    AlbumSummary.dummy(id: "album.1"),
                    AlbumSummary.dummy(id: "album.2"),
                    AlbumSummary.dummy(id: "album.3")
                ],
                looped: false
            ),
            assetsPlaylists: [
                AlbumID(rawValue: "album.1"): Playlist(
                    elements: [AlbumAsset.dummy(id: "asset.1")],
                    looped: false
                ),
                AlbumID(rawValue: "album.2"): Playlist(elements: [], looped: false),
                AlbumID(rawValue: "album.3"): Playlist(
                    elements: [AlbumAsset.dummy(id: "asset.2")],
                    looped: false
                )
            ]
        )

        let slideshow = try await SlideshowSequencer(
            playlistGetter: playlistGetter,
            initialAlbumID: AlbumID(rawValue: "album.1"),
            initialAssetID: nil
        )

        let next = try #require(await slideshow.next())
        #expect(next.album.id.string == "album.3")
        #expect(next.asset.id.string == "asset.2")
    }

    @Test func emptyInitialAlbumStartsAtFirstNonEmpty() async throws {
        let playlistGetter = FakePlaylistGetter(
            albumPlaylist: Playlist(
                elements: [
                    AlbumSummary.dummy(id: "album.1"),
                    AlbumSummary.dummy(id: "album.2")
                ],
                looped: false
            ),
            assetsPlaylists: [
                AlbumID(rawValue: "album.1"): Playlist(elements: [], looped: false),
                AlbumID(rawValue: "album.2"): Playlist(
                    elements: [AlbumAsset.dummy(id: "asset.1")],
                    looped: false
                )
            ]
        )

        let slideshow = try await SlideshowSequencer(
            playlistGetter: playlistGetter,
            initialAlbumID: AlbumID(rawValue: "album.1"),
            initialAssetID: nil
        )

        let current = try #require(await slideshow.current())
        #expect(current.album.id.string == "album.2")
        #expect(current.asset.id.string == "asset.1")
    }

    @Test func allAlbumsEmptyReturnsNilWithoutCrashing() async throws {
        let playlistGetter = FakePlaylistGetter(
            albumPlaylist: Playlist(
                elements: [AlbumSummary.dummy(id: "album.1")],
                looped: false
            ),
            assetsPlaylists: [
                AlbumID(rawValue: "album.1"): Playlist(elements: [], looped: false)
            ]
        )

        let slideshow = try await SlideshowSequencer(
            playlistGetter: playlistGetter,
            initialAlbumID: AlbumID(rawValue: "album.1"),
            initialAssetID: nil
        )

        let current = try await slideshow.current()
        #expect(current == nil)

        let next = try await slideshow.next()
        #expect(next == nil)
    }
}

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

@MainActor
struct SlideshowSequencerPreviewTests {
    private func singleAlbumGetter() -> FakePlaylistGetter {
        FakePlaylistGetter(
            albumPlaylist: Playlist(
                elements: [AlbumSummary.dummy(id: "album.1")],
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
    }

    @Test func previewNextReturnsTheNextCountWithoutAdvancing() async throws {
        let slideshow = try await SlideshowSequencer(
            playlistGetter: singleAlbumGetter(),
            initialAlbumID: AlbumID(rawValue: "album.1"),
            initialAssetID: nil
        )

        let previewed = try await slideshow.previewNext(count: 2)
        #expect(previewed.map(\.asset.id.string) == ["asset.2", "asset.3"])

        // Position is unchanged after previewing.
        let current = try #require(await slideshow.current())
        #expect(current.asset.id.string == "asset.1")
    }

    @Test func previewNextStopsAtTheEndWhenNotLooping() async throws {
        let slideshow = try await SlideshowSequencer(
            playlistGetter: singleAlbumGetter(),
            initialAlbumID: AlbumID(rawValue: "album.1"),
            initialAssetID: nil
        )

        let previewed = try await slideshow.previewNext(count: 5)
        #expect(previewed.map(\.asset.id.string) == ["asset.2", "asset.3"])
    }

    @Test func previewPreviousReturnsThePreviousCountNearestFirst() async throws {
        let slideshow = try await SlideshowSequencer(
            playlistGetter: singleAlbumGetter(),
            initialAlbumID: AlbumID(rawValue: "album.1"),
            initialAssetID: AssetID(rawValue: "asset.3")
        )

        let previewed = try await slideshow.previewPrevious(count: 5)
        #expect(previewed.map(\.asset.id.string) == ["asset.2", "asset.1"])
    }

    @Test func previewNextCrossesAlbumsAndSkipsEmptyOnes() async throws {
        let playlistGetter = FakePlaylistGetter(
            albumPlaylist: Playlist(
                elements: [
                    AlbumSummary.dummy(id: "album.1"),
                    AlbumSummary.dummy(id: "album.2"),
                    AlbumSummary.dummy(id: "album.3")
                ],
                looped: false
            ),
            assetsPlaylists: [
                AlbumID(rawValue: "album.1"): Playlist(
                    elements: [AlbumAsset.dummy(id: "asset.1")],
                    looped: false
                ),
                AlbumID(rawValue: "album.2"): Playlist(elements: [], looped: false),
                AlbumID(rawValue: "album.3"): Playlist(
                    elements: [AlbumAsset.dummy(id: "asset.2")],
                    looped: false
                )
            ]
        )

        let slideshow = try await SlideshowSequencer(
            playlistGetter: playlistGetter,
            initialAlbumID: AlbumID(rawValue: "album.1"),
            initialAssetID: nil
        )

        let previewed = try await slideshow.previewNext(count: 3)
        #expect(previewed.map(\.asset.id.string) == ["asset.2"])
    }
}
