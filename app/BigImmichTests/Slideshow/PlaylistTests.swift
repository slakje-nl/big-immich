//
//  PlaylistTests.swift
//  BigImmich
//
//  Created by Maciej Płoński on 18/01/2026.
//

@testable import BigImmich
import ImmichAPI
import Testing
import XCTest

@MainActor
struct PlaylistGetterAlbumsTests {
    @Test func getSingleAlbumStopAtTheEnd() async throws {
        let settings = FakeSettings(
            slideshowOnceEndedAction: .stopAndNotify,
            slideshowOnceEndedAnotherAlbumSelection: .random,
            slideshowDirection: .oldestToNewest
        )

        let fakeClient = FakeImmichClient(
            albumSummaries: [
                AlbumSummary.dummy(id: "album.1"),
                AlbumSummary.dummy(id: "album.2"),
                AlbumSummary.dummy(id: "album.3")
            ],
            albums: [
                AlbumID(rawValue: "album.2"): Album.dummy(
                    id: "album.2",
                    assets: [
                        AlbumAsset.dummy(id: "asset.1"),
                        AlbumAsset.dummy(id: "asset.2"),
                        AlbumAsset.dummy(id: "asset.3")
                    ]
                )
            ]
        )

        let playlistGetter = SlideshowPlaylistGetter(
            settings: settings,
            immichClient: fakeClient
        )

        let albums = try await playlistGetter.getAlbumsPlaylist(
            initialAlbumID: AlbumID(rawValue: "album.2")
        )

        XCTAssertEqual(albums.looped, false)
        XCTAssertEqual(albums.elements.count, 1)
        XCTAssertEqual(albums.elements[0].id.string, "album.2")
    }

    @Test func getSingleAlbumLooped() async throws {
        let settings = FakeSettings(
            slideshowOnceEndedAction: .startAgain,
            slideshowOnceEndedAnotherAlbumSelection: .random,
            slideshowDirection: .oldestToNewest
        )

        let fakeClient = FakeImmichClient(
            albumSummaries: [
                AlbumSummary.dummy(id: "album.1"),
                AlbumSummary.dummy(id: "album.2"),
                AlbumSummary.dummy(id: "album.3")
            ],
            albums: [
                AlbumID(rawValue: "album.2"): Album.dummy(
                    id: "album.2",
                    assets: [
                        AlbumAsset.dummy(id: "asset.1"),
                        AlbumAsset.dummy(id: "asset.2"),
                        AlbumAsset.dummy(id: "asset.3")
                    ]
                )
            ]
        )

        let playlistGetter = SlideshowPlaylistGetter(
            settings: settings,
            immichClient: fakeClient
        )

        let albums = try await playlistGetter.getAlbumsPlaylist(
            initialAlbumID: AlbumID(rawValue: "album.2")
        )

        XCTAssertEqual(albums.looped, true)
        XCTAssertEqual(albums.elements.count, 1)
        XCTAssertEqual(albums.elements[0].id.string, "album.2")
    }

    @Test func getMultipleAlbumsNextOlder() async throws {
        let settings = FakeSettings(
            slideshowOnceEndedAction: .loadAnotherAlbum,
            slideshowOnceEndedAnotherAlbumSelection: .older,
            slideshowDirection: .oldestToNewest
        )

        let fakeClient = FakeImmichClient(
            albumSummaries: [
                AlbumSummary.dummy(id: "album.1"),
                AlbumSummary.dummy(id: "album.2")
            ],
            albums: [
                AlbumID(rawValue: "album.1"): Album.dummy(
                    id: "album.1",
                    assets: [
                        AlbumAsset.dummy(id: "asset.1"),
                        AlbumAsset.dummy(id: "asset.2")
                    ]
                ),
                AlbumID(rawValue: "album.2"): Album.dummy(
                    id: "album.2",
                    assets: [
                        AlbumAsset.dummy(id: "asset.3"),
                        AlbumAsset.dummy(id: "asset.4")
                    ]
                )
            ]
        )

        let playlistGetter = SlideshowPlaylistGetter(
            settings: settings,
            immichClient: fakeClient
        )

        let albums = try await playlistGetter.getAlbumsPlaylist(
            initialAlbumID: AlbumID(rawValue: "album.2")
        )

        XCTAssertEqual(albums.looped, true)
        XCTAssertEqual(albums.elements.count, 2)
        XCTAssertEqual(albums.elements[0].id.string, "album.1")
        XCTAssertEqual(albums.elements[1].id.string, "album.2")
        XCTAssertEqual(fakeClient.lastAlbumsOrder, .fromNewest)
    }

    @Test func getMultipleAlbumsNextNewer() async throws {
        let settings = FakeSettings(
            slideshowOnceEndedAction: .loadAnotherAlbum,
            slideshowOnceEndedAnotherAlbumSelection: .newer,
            slideshowDirection: .oldestToNewest
        )

        let fakeClient = FakeImmichClient(
            albumSummaries: [
                AlbumSummary.dummy(id: "album.1"),
                AlbumSummary.dummy(id: "album.2")
            ],
            albums: [
                AlbumID(rawValue: "album.1"): Album.dummy(
                    id: "album.1",
                    assets: [
                        AlbumAsset.dummy(id: "asset.1"),
                        AlbumAsset.dummy(id: "asset.2")
                    ]
                ),
                AlbumID(rawValue: "album.2"): Album.dummy(
                    id: "album.2",
                    assets: [
                        AlbumAsset.dummy(id: "asset.3"),
                        AlbumAsset.dummy(id: "asset.4")
                    ]
                )
            ]
        )

        let playlistGetter = SlideshowPlaylistGetter(
            settings: settings,
            immichClient: fakeClient
        )

        let albums = try await playlistGetter.getAlbumsPlaylist(
            initialAlbumID: AlbumID(rawValue: "album.2")
        )

        XCTAssertEqual(albums.looped, true)
        XCTAssertEqual(albums.elements.count, 2)
        XCTAssertEqual(albums.elements[0].id.string, "album.1")
        XCTAssertEqual(albums.elements[1].id.string, "album.2")
        XCTAssertEqual(fakeClient.lastAlbumsOrder, .fromOldest)
    }

    @Test func getMultipleAlbumsRandom() async throws {
        let settings = FakeSettings(
            slideshowOnceEndedAction: .loadAnotherAlbum,
            slideshowOnceEndedAnotherAlbumSelection: .random,
            slideshowDirection: .oldestToNewest
        )

        let fakeClient = FakeImmichClient(
            albumSummaries: [
                AlbumSummary.dummy(id: "album.1"),
                AlbumSummary.dummy(id: "album.2"),
                AlbumSummary.dummy(id: "album.3")
            ],
            albums: [:]
        )

        let playlistGetter = SlideshowPlaylistGetter(
            settings: settings,
            immichClient: fakeClient
        )

        let albums = try await playlistGetter.getAlbumsPlaylist(
            initialAlbumID: AlbumID(rawValue: "album.1")
        )

        #expect(albums.looped)
        #expect(albums.elements.count == 3)
        #expect(
            Set(albums.elements.map(\.id.string)) == ["album.1", "album.2", "album.3"]
        )
        #expect(fakeClient.lastAlbumsOrder == .fromNewest)
    }
}

@MainActor
struct PlaylistGetterAssetsTests {
    @Test func stopAndNotifyFromOldest() async throws {
        let settings = FakeSettings(
            slideshowOnceEndedAction: .stopAndNotify,
            slideshowOnceEndedAnotherAlbumSelection: .random,
            slideshowDirection: .oldestToNewest
        )

        let fakeClient = FakeImmichClient(
            albumSummaries: [
                AlbumSummary.dummy(id: "album.1"),
                AlbumSummary.dummy(id: "album.2"),
                AlbumSummary.dummy(id: "album.3")
            ],
            albums: [
                AlbumID(rawValue: "album.2"): Album.dummy(
                    id: "album.2",
                    assets: [
                        AlbumAsset.dummy(id: "asset.1"),
                        AlbumAsset.dummy(id: "asset.2"),
                        AlbumAsset.dummy(id: "asset.3")
                    ]
                )
            ]
        )

        let playlistGetter = SlideshowPlaylistGetter(
            settings: settings,
            immichClient: fakeClient
        )

        let assets = try await playlistGetter.getAssetsPlaylist(
            albumID: AlbumID(rawValue: "album.2")
        )

        XCTAssertEqual(assets.looped, false)
        XCTAssertEqual(assets.elements.count, 3)
        XCTAssertEqual(assets.elements[0].id.string, "asset.3")
        XCTAssertEqual(assets.elements[1].id.string, "asset.2")
        XCTAssertEqual(assets.elements[2].id.string, "asset.1")
    }

    @Test func stopAndNotifyFromNewest() async throws {
        let settings = FakeSettings(
            slideshowOnceEndedAction: .stopAndNotify,
            slideshowOnceEndedAnotherAlbumSelection: .random,
            slideshowDirection: .newestToOldest
        )

        let fakeClient = FakeImmichClient(
            albumSummaries: [
                AlbumSummary.dummy(id: "album.1"),
                AlbumSummary.dummy(id: "album.2"),
                AlbumSummary.dummy(id: "album.3")
            ],
            albums: [
                AlbumID(rawValue: "album.2"): Album.dummy(
                    id: "album.2",
                    assets: [
                        AlbumAsset.dummy(id: "asset.1"),
                        AlbumAsset.dummy(id: "asset.2"),
                        AlbumAsset.dummy(id: "asset.3")
                    ]
                )
            ]
        )

        let playlistGetter = SlideshowPlaylistGetter(
            settings: settings,
            immichClient: fakeClient
        )

        let assets = try await playlistGetter.getAssetsPlaylist(
            albumID: AlbumID(rawValue: "album.2")
        )

        XCTAssertEqual(assets.looped, false)
        XCTAssertEqual(assets.elements.count, 3)
        XCTAssertEqual(assets.elements[0].id.string, "asset.1")
        XCTAssertEqual(assets.elements[1].id.string, "asset.2")
        XCTAssertEqual(assets.elements[2].id.string, "asset.3")
    }

    @Test func multipleAlbums() async throws {
        let settings = FakeSettings(
            slideshowOnceEndedAction: .loadAnotherAlbum,
            slideshowOnceEndedAnotherAlbumSelection: .random,
            slideshowDirection: .newestToOldest
        )

        let fakeClient = FakeImmichClient(
            albumSummaries: [
                AlbumSummary.dummy(id: "album.1"),
                AlbumSummary.dummy(id: "album.2"),
                AlbumSummary.dummy(id: "album.3")
            ],
            albums: [
                AlbumID(rawValue: "album.2"): Album.dummy(
                    id: "album.2",
                    assets: [
                        AlbumAsset.dummy(id: "asset.1"),
                        AlbumAsset.dummy(id: "asset.2"),
                        AlbumAsset.dummy(id: "asset.3")
                    ]
                )
            ]
        )

        let playlistGetter = SlideshowPlaylistGetter(
            settings: settings,
            immichClient: fakeClient
        )

        let assets = try await playlistGetter.getAssetsPlaylist(
            albumID: AlbumID(rawValue: "album.2")
        )

        XCTAssertEqual(assets.looped, false)
    }

    @Test func repeatAlbum() async throws {
        let settings = FakeSettings(
            slideshowOnceEndedAction: .startAgain,
            slideshowOnceEndedAnotherAlbumSelection: .random,
            slideshowDirection: .newestToOldest
        )

        let fakeClient = FakeImmichClient(
            albumSummaries: [
                AlbumSummary.dummy(id: "album.1"),
                AlbumSummary.dummy(id: "album.2"),
                AlbumSummary.dummy(id: "album.3")
            ],
            albums: [
                AlbumID(rawValue: "album.2"): Album.dummy(
                    id: "album.2",
                    assets: [
                        AlbumAsset.dummy(id: "asset.1"),
                        AlbumAsset.dummy(id: "asset.2"),
                        AlbumAsset.dummy(id: "asset.3")
                    ]
                )
            ]
        )

        let playlistGetter = SlideshowPlaylistGetter(
            settings: settings,
            immichClient: fakeClient
        )

        let assets = try await playlistGetter.getAssetsPlaylist(
            albumID: AlbumID(rawValue: "album.2")
        )

        XCTAssertEqual(assets.looped, true)
    }

    @Test func randomizedDirectionKeepsSameAssets() async throws {
        let settings = FakeSettings(
            slideshowOnceEndedAction: .stopAndNotify,
            slideshowOnceEndedAnotherAlbumSelection: .random,
            slideshowDirection: .randomized
        )

        let fakeClient = FakeImmichClient(
            albumSummaries: [AlbumSummary.dummy(id: "album.1")],
            albums: [
                AlbumID(rawValue: "album.1"): Album.dummy(
                    id: "album.1",
                    assets: [
                        AlbumAsset.dummy(id: "asset.1"),
                        AlbumAsset.dummy(id: "asset.2"),
                        AlbumAsset.dummy(id: "asset.3")
                    ]
                )
            ]
        )

        let playlistGetter = SlideshowPlaylistGetter(
            settings: settings,
            immichClient: fakeClient
        )

        let assets = try await playlistGetter.getAssetsPlaylist(
            albumID: AlbumID(rawValue: "album.1")
        )

        #expect(assets.elements.count == 3)
        #expect(
            Set(assets.elements.map(\.id.string)) == ["asset.1", "asset.2", "asset.3"]
        )
    }
}
