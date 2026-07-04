@testable import ImmichAPI
import Testing

struct AssetTypeTests {
    private func asset(type: String) -> AlbumAsset {
        AlbumAsset(id: AssetID(rawValue: "a"), type: type, durationMilliseconds: nil)
    }

    @Test func mapsKnownTypesCaseInsensitively() {
        #expect(asset(type: "IMAGE").assetType == .image)
        #expect(asset(type: "image").assetType == .image)
        #expect(asset(type: "VIDEO").assetType == .video)
        #expect(asset(type: "video").assetType == .video)
    }

    @Test func mapsUnknownTypeToOther() {
        #expect(asset(type: "AUDIO").assetType == .other)
        #expect(asset(type: "").assetType == .other)
    }
}

struct JoinAlbumsTests {
    private func summary(id: String, startDate: String, assetCount: Int? = 1) -> AlbumSummary {
        AlbumSummary(
            id: AlbumID(rawValue: id),
            albumName: AlbumName(rawValue: id),
            albumThumbnailAssetId: AssetID(rawValue: "t"),
            startDate: startDate,
            assetCount: assetCount
        )
    }

    @Test func deduplicatesAcrossLists() {
        let own = [summary(id: "a", startDate: "2025-01-01")]
        let shared = [
            summary(id: "a", startDate: "2025-01-01"),
            summary(id: "b", startDate: "2025-02-01")
        ]
        #expect(joinAlbums(order: .fromNewest, albumLists: [own, shared]).map(\.id.string) == ["b", "a"])
    }

    @Test func sortsByStartDate() {
        let albums = [
            summary(id: "old", startDate: "2024-01-01"),
            summary(id: "new", startDate: "2025-01-01")
        ]
        #expect(joinAlbums(order: .fromOldest, albumLists: [albums]).map(\.id.string) == ["old", "new"])
        #expect(joinAlbums(order: .fromNewest, albumLists: [albums]).map(\.id.string) == ["new", "old"])
    }

    @Test func hidesEmptyAlbumsKeepingUnknownCounts() {
        let albums = [
            summary(id: "full", startDate: "2025-01-01", assetCount: 3),
            summary(id: "empty", startDate: "2025-02-01", assetCount: 0),
            summary(id: "unknown", startDate: "2025-03-01", assetCount: nil)
        ]
        #expect(joinAlbums(order: .fromOldest, albumLists: [albums]).map(\.id.string) == ["full", "unknown"])
    }
}
