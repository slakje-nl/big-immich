import Foundation
@testable import ImmichAPI
import Testing

struct ModelDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func decodesAlbumSummaryIgnoringUnknownKeys() throws {
        let summary = try decode(
            AlbumSummary.self,
            from: """
            {
                "id": "album-1",
                "albumName": "Holidays",
                "albumThumbnailAssetId": "asset-9",
                "createdAt": "2025-11-19T19:52:35.661517+00:00",
                "updatedAt": "2025-11-19T19:52:39.064032+00:00",
                "startDate": "2025-11-06T00:00:00.000Z",
                "lastModifiedAssetTimestamp": "2025-11-19T21:07:02.749Z",
                "ownerId": "ignored-unknown-key"
            }
            """
        )

        #expect(summary.id.string == "album-1")
        #expect(summary.albumName.string == "Holidays")
        #expect(summary.albumThumbnailAssetId?.string == "asset-9")
        #expect(summary.startDate == "2025-11-06T00:00:00.000Z")
    }

    @Test func decodesSearchResponseAssets() throws {
        let response = try decode(
            SearchResponse.self,
            from: """
            {
                "assets": {
                    "count": 2,
                    "nextPage": "2",
                    "items": [
                        {
                            "id": "asset-1",
                            "type": "IMAGE",
                            "duration": null,
                            "exifInfo": {
                                "dateTimeOriginal": "2025-11-06T10:15:00.000+00:00",
                                "city": "Amsterdam",
                                "state": "North Holland",
                                "country": "Netherlands"
                            }
                        },
                        {
                            "id": "asset-2",
                            "type": "VIDEO",
                            "duration": 12500
                        }
                    ]
                }
            }
            """
        )

        #expect(response.assets.items.count == 2)
        #expect(response.assets.items[0].exifInfo?.city == "Amsterdam")
        #expect(response.assets.items[0].durationMilliseconds == nil)
        #expect(response.assets.items[1].exifInfo == nil)
        #expect(response.assets.items[1].durationMilliseconds == 12500)
        #expect(response.assets.nextPage == "2")
    }

    @Test func decodesAssetWithPartialExif() throws {
        let asset = try decode(
            AlbumAsset.self,
            from: """
            {
                "id": "asset-3",
                "type": "IMAGE",
                "duration": null,
                "exifInfo": { "dateTimeOriginal": null, "city": "Berlin" }
            }
            """
        )

        #expect(asset.exifInfo?.city == "Berlin")
        #expect(asset.exifInfo?.state == nil)
        #expect(asset.exifInfo?.dateTimeOriginal == nil)
    }

    @Test func decodesAlbumMetadataWithoutAssets() throws {
        let album = try decode(
            Album.self,
            from: """
            {
                "id": "album-1",
                "albumName": "Holidays",
                "albumThumbnailAssetId": "asset-9",
                "createdAt": "2025-11-19T19:52:35.661517+00:00",
                "updatedAt": "2025-11-19T19:52:39.064032+00:00",
                "startDate": "2025-11-06T00:00:00.000Z",
                "lastModifiedAssetTimestamp": "2025-11-19T21:07:02.749Z",
                "assetCount": 5
            }
            """
        )

        #expect(album.id.string == "album-1")
        #expect(album.albumName.string == "Holidays")
    }

    @Test func customStringIdRoundTrips() throws {
        let original = AssetID(rawValue: "abc-123")
        let data = try JSONEncoder().encode(original)

        #expect(String(data: data, encoding: .utf8) == "\"abc-123\"")
        #expect(try JSONDecoder().decode(AssetID.self, from: data) == original)
    }

    @Test func lossyArraySkipsInvalidElements() throws {
        let summaries = try decode(
            LossyArray<AlbumSummary>.self,
            from: """
            [
                {
                    "id": "album-1",
                    "albumName": "Ok",
                    "albumThumbnailAssetId": "asset-9",
                    "createdAt": "2025-11-19T19:52:35.661517+00:00",
                    "updatedAt": "2025-11-19T19:52:39.064032+00:00",
                    "startDate": "2025-11-06T00:00:00.000Z",
                    "lastModifiedAssetTimestamp": "2025-11-19T21:07:02.749Z"
                },
                { "id": "album-2" }
            ]
            """
        ).elements

        #expect(summaries.count == 1)
        #expect(summaries[0].id.string == "album-1")
    }

    @Test func lossyArrayHandlesEmptyAndAllInvalid() throws {
        let empty = try decode(LossyArray<AlbumSummary>.self, from: "[]").elements
        #expect(empty.isEmpty)

        let allInvalid = try decode(
            LossyArray<AlbumSummary>.self,
            from: "[{ \"id\": \"x\" }, { \"nope\": true }]"
        ).elements
        #expect(allInvalid.isEmpty)
    }
}
