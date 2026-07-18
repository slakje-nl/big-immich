@testable import BigImmich
import Foundation
import ImmichAPI
import Testing

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

struct AlbumImageCountTests {
    @Test func subtractsVideosFromTheTotal() {
        #expect(albumImageCount(assetCount: 10, videoCount: 3) == 7)
    }

    @Test func neverGoesNegative() {
        #expect(albumImageCount(assetCount: 2, videoCount: 5) == 0)
    }

    @Test func unknownTotalReturnsNil() {
        #expect(albumImageCount(assetCount: nil, videoCount: 3) == nil)
    }

    @Test func allVideosLeaveNoImages() {
        #expect(albumImageCount(assetCount: 4, videoCount: 4) == 0)
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

struct SlideshowDurationCacheTests {
    private func makeCache() -> SlideshowDurationCache {
        SlideshowDurationCache(store: CodableDiskCache(name: "test-\(UUID().uuidString)"))
    }

    private func info(token: String) -> SlideshowDurationInfo {
        SlideshowDurationInfo(token: token, assetCount: 5, videoCount: 2, videoDurationMilliseconds: 1000)
    }

    @Test func freshReturnsInfoOnTokenMatch() {
        let cache = makeCache()
        let id = AlbumID(rawValue: "a")
        cache.set(albumID: id, info: info(token: "t1"))
        #expect(cache.fresh(albumID: id, token: "t1")?.videoCount == 2)
        cache.clear()
    }

    @Test func freshReturnsNilOnTokenMismatch() {
        let cache = makeCache()
        let id = AlbumID(rawValue: "a")
        cache.set(albumID: id, info: info(token: "t1"))
        #expect(cache.fresh(albumID: id, token: "t2") == nil)
        cache.clear()
    }

    @Test func cachedReturnsRegardlessOfToken() {
        let cache = makeCache()
        let id = AlbumID(rawValue: "a")
        cache.set(albumID: id, info: info(token: "t1"))
        #expect(cache.cached(albumID: id)?.assetCount == 5)
        cache.clear()
    }

    @Test func tokenChangesWithAssetCountOrTimestamp() {
        let base = SlideshowDurationCache.token(assetCount: 5, lastModifiedAssetTimestamp: "2026-01-01")
        #expect(base != SlideshowDurationCache.token(assetCount: 6, lastModifiedAssetTimestamp: "2026-01-01"))
        #expect(base != SlideshowDurationCache.token(assetCount: 5, lastModifiedAssetTimestamp: "2026-02-02"))
        #expect(base == SlideshowDurationCache.token(assetCount: 5, lastModifiedAssetTimestamp: "2026-01-01"))
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
