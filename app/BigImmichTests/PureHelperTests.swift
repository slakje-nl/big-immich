@testable import BigImmich
import Foundation
import ImmichAPI
import Testing

struct SlideshowDurationTests {
    private func image() -> AlbumAsset {
        AlbumAsset(id: AssetID(rawValue: "img"), type: "IMAGE", originalPath: "", duration: "0:00:00.00000")
    }

    private func video(_ duration: String) -> AlbumAsset {
        AlbumAsset(id: AssetID(rawValue: "vid"), type: "VIDEO", originalPath: "", duration: duration)
    }

    @Test func imagesUseTheInterval() {
        #expect(slideshowDurationMinutes(items: [image(), image()], imageInterval: 30) == 1)
    }

    @Test func videoDurationIsParsedAndRoundedUp() {
        #expect(slideshowDurationMinutes(items: [video("0:01:30.500")], imageInterval: 5) == 2)
    }

    @Test func malformedVideoDurationIsIgnored() {
        #expect(slideshowDurationMinutes(items: [video("nonsense")], imageInterval: 5) == 0)
    }

    @Test func mixedItemsRoundUpToWholeMinutes() {
        #expect(slideshowDurationMinutes(items: [image(), video("0:00:40.000")], imageInterval: 5) == 1)
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
        AlbumAsset(id: AssetID(rawValue: "a"), type: "IMAGE", originalPath: "", duration: "0:00:00", exifInfo: exif)
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

    @Test func returnsEmptyLocationWhenIncomplete() {
        #expect(formattedLocation(asset(exif: nil)).isEmpty)
        let partial = ExifInfo(dateTimeOriginal: nil, city: "Amsterdam", state: nil, country: "NL")
        #expect(formattedLocation(asset(exif: partial)).isEmpty)
    }
}
