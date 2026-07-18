@testable import BigImmich
import Foundation
import ImmichAPI
import Testing

struct ServerVersionTests {
    @Test func comparesByComponents() {
        #expect(ServerVersion(major: 3, minor: 0, patch: 1) < ServerVersion(major: 3, minor: 1, patch: 0))
        #expect(ServerVersion(major: 3, minor: 0, patch: 2) > ServerVersion(major: 3, minor: 0, patch: 1))
        #expect(!(ServerVersion(major: 3, minor: 0, patch: 1) < ServerVersion(major: 3, minor: 0, patch: 1)))
    }

    @Test func displayStringJoinsComponents() {
        #expect(ServerVersion(major: 3, minor: 0, patch: 1).displayString == "3.0.1")
    }

    @Test func decodesFromJSON() throws {
        let data = Data(#"{"major":3,"minor":2,"patch":5}"#.utf8)
        let version = try JSONDecoder().decode(ServerVersion.self, from: data)
        #expect(version == ServerVersion(major: 3, minor: 2, patch: 5))
    }
}

struct SlideshowDurationTests {
    @Test func imagesUseTheInterval() {
        #expect(slideshowDurationMinutes(imageCount: 2, videoDurationMilliseconds: 0, imageInterval: 30) == 1)
    }

    @Test func videoDurationIsRoundedUp() {
        #expect(slideshowDurationMinutes(imageCount: 0, videoDurationMilliseconds: 90500, imageInterval: 5) == 2)
    }

    @Test func noVideoDurationCountsAsZero() {
        #expect(slideshowDurationMinutes(imageCount: 0, videoDurationMilliseconds: 0, imageInterval: 5) == 0)
    }

    @Test func mixedItemsRoundUpToWholeMinutes() {
        #expect(slideshowDurationMinutes(imageCount: 1, videoDurationMilliseconds: 40000, imageInterval: 5) == 1)
    }
}

struct ImageDiskCacheTests {
    private func makeCache() -> ImageDiskCache {
        ImageDiskCache(directoryName: "test-\(UUID().uuidString)")
    }

    @Test func storesAndReadsBack() {
        let cache = makeCache()
        let payload = Data("hello".utf8)
        cache.store(payload, forKey: "k")
        #expect(cache.data(forKey: "k") == payload)
        cache.clear()
    }

    @Test func missingKeyReturnsNil() {
        let cache = makeCache()
        #expect(cache.data(forKey: "absent") == nil)
    }

    @Test func clearEmptiesTheCache() {
        let cache = makeCache()
        cache.store(Data("abc".utf8), forKey: "a")
        cache.store(Data("defgh".utf8), forKey: "b")
        #expect(cache.totalSizeBytes() == 8)
        cache.clear()
        #expect(cache.totalSizeBytes() == 0)
        #expect(cache.data(forKey: "a") == nil)
    }
}

struct CodableDiskCacheTests {
    private func makeCache() -> CodableDiskCache<[String]> {
        CodableDiskCache(name: "test-\(UUID().uuidString)")
    }

    @Test func storesAndReadsBackCodable() {
        let cache = makeCache()
        cache.store(["a", "b"], forKey: "k")
        #expect(cache.value(forKey: "k") == ["a", "b"])
        cache.clear()
    }

    @Test func missingKeyReturnsNil() {
        let cache = makeCache()
        #expect(cache.value(forKey: "absent") == nil)
    }

    @Test func clearEmptiesTheCache() {
        let cache = makeCache()
        cache.store(["x"], forKey: "a")
        #expect(cache.totalSizeBytes() > 0)
        cache.clear()
        #expect(cache.totalSizeBytes() == 0)
        #expect(cache.value(forKey: "a") == nil)
    }
}

struct AlbumMetadataCacheTests {
    private func store<T: Codable & Sendable>() -> CodableDiskCache<T> {
        CodableDiskCache(name: "test-\(UUID().uuidString)")
    }

    @Test func albumsListCacheKeysByOrder() {
        let cache = AlbumsListCache(store: store())
        cache.set(order: .fromNewest, albums: [AlbumSummary.dummy(id: "a")])
        #expect(cache.cached(order: .fromNewest)?.map(\.id.string) == ["a"])
        #expect(cache.cached(order: .fromOldest) == nil)
        cache.clear()
    }

    @Test func albumDetailCacheRoundTrips() {
        let cache = AlbumDetailCache(store: store())
        let album = Album.dummy(id: "album.1")
        cache.set(album)
        #expect(cache.cached(albumID: AlbumID(rawValue: "album.1"))?.id == album.id)
        #expect(cache.cached(albumID: AlbumID(rawValue: "missing")) == nil)
        cache.clear()
    }

    @Test func albumAssetsCacheRoundTrips() {
        let cache = AlbumAssetsCache(store: store())
        let id = AlbumID(rawValue: "album.1")
        cache.set(albumID: id, assets: [AlbumAsset.dummy(id: "asset.1")])
        #expect(cache.cached(albumID: id)?.map(\.id.string) == ["asset.1"])
        #expect(cache.cached(albumID: AlbumID(rawValue: "missing")) == nil)
        cache.clear()
    }
}

struct TopShelfLinkTests {
    private func link(_ string: String) -> TopShelfAlbumLink? {
        guard let url = URL(string: string) else { return nil }
        return parseTopShelfAlbumLink(url)
    }

    @Test func parsesValidLink() throws {
        let parsed = try #require(link("bigimmich://album/details?albumID=abc&albumName=Trip"))
        #expect(parsed.albumID.string == "abc")
        #expect(parsed.albumName.string == "Trip")
    }

    @Test func rejectsWrongSchemeHostOrPath() {
        #expect(link("https://album/details?albumID=a&albumName=b") == nil)
        #expect(link("bigimmich://asset/details?albumID=a&albumName=b") == nil)
        #expect(link("bigimmich://album/other?albumID=a&albumName=b") == nil)
    }

    @Test func rejectsMissingParameters() {
        #expect(link("bigimmich://album/details?albumID=a") == nil)
        #expect(link("bigimmich://album/details?albumName=b") == nil)
    }
}

struct URLValidationTests {
    @Test func acceptsHTTPAndHTTPS() {
        #expect(isValidHTTPURL("http://immich.local"))
        #expect(isValidHTTPURL("https://immich.example.com:2283"))
    }

    @Test func rejectsNonHTTPOrHostless() {
        #expect(!isValidHTTPURL(""))
        #expect(!isValidHTTPURL("immich.local"))
        #expect(!isValidHTTPURL("ftp://immich.local"))
    }
}

struct AssetMetadataFormattingTests {
    private func asset(exif: ExifInfo?) -> AlbumAsset {
        AlbumAsset(id: AssetID(rawValue: "a"), type: "IMAGE", durationMilliseconds: nil, exifInfo: exif)
    }

    @Test func formatsCaptureDateWhenPresent() {
        let exif = ExifInfo(dateTimeOriginal: "2025-11-06T10:15:00.000+00:00", city: nil, state: nil, country: nil)
        #expect(!formattedCaptureDate(asset(exif: exif)).isEmpty)
    }

    @Test func returnsEmptyDateWhenMissingOrUnparseable() {
        #expect(formattedCaptureDate(asset(exif: nil)).isEmpty)
        let unparseable = ExifInfo(dateTimeOriginal: "not-a-date", city: nil, state: nil, country: nil)
        #expect(formattedCaptureDate(asset(exif: unparseable)).isEmpty)
    }

    @Test func formatsFullLocation() {
        let exif = ExifInfo(dateTimeOriginal: nil, city: "Amsterdam", state: "NH", country: "NL")
        #expect(formattedLocation(asset(exif: exif)) == "Amsterdam, NH, NL")
    }

    @Test func returnsEmptyLocationWithoutExif() {
        #expect(formattedLocation(asset(exif: nil)).isEmpty)
    }

    @Test func joinsAvailableLocationParts() {
        let partial = ExifInfo(dateTimeOriginal: nil, city: "Amsterdam", state: nil, country: "NL")
        #expect(formattedLocation(asset(exif: partial)) == "Amsterdam, NL")
    }
}
