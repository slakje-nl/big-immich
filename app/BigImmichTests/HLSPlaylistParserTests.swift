import Foundation
import ImmichAPI
import Testing

struct HLSPlaylistParserTests {
    private let masterURL = URL(
        string: "https://immich.test/api/assets/asset-1/video/stream/main.m3u8"
    )!

    private let playlist = """
    #EXTM3U
    #EXT-X-VERSION:7
    #EXT-X-INDEPENDENT-SEGMENTS
    #EXT-X-STREAM-INF:BANDWIDTH=10800000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2",VIDEO-RANGE=SDR,FRAME-RATE=29.970
    sess-abc/8/playlist.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=6750000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2",VIDEO-RANGE=SDR,FRAME-RATE=29.970
    sess-abc/5/playlist.m3u8

    """

    @Test func parsesEveryVariant() {
        let variants = HLSPlaylistParser.parseVariants(playlist: playlist, masterURL: masterURL)
        #expect(variants.count == 2)
        #expect(variants[0].heightPixels == 1080)
        #expect(variants[0].widthPixels == 1920)
        #expect(variants[0].bandwidth == 10_800_000)
        #expect(variants[0].index == 8)
        #expect(variants[1].heightPixels == 720)
        #expect(variants[1].index == 5)
    }

    @Test func resolvesRelativeURIsAgainstTheMaster() {
        let variants = HLSPlaylistParser.parseVariants(playlist: playlist, masterURL: masterURL)
        #expect(
            variants[0].playlistURL.absoluteString
                == "https://immich.test/api/assets/asset-1/video/stream/sess-abc/8/playlist.m3u8"
        )
    }

    @Test func extractsSessionIDFromVariantPath() {
        #expect(
            HLSPlaylistParser.sessionID(fromVariantURI: "sess-abc/8/playlist.m3u8") == "sess-abc"
        )
        #expect(
            HLSPlaylistParser
                .sessionID(fromVariantURI: "/api/assets/x/video/stream/sess-xyz/3/playlist.m3u8") == "sess-xyz"
        )
    }

    @Test func ignoresPlaylistsWithoutVariants() {
        let empty = "#EXTM3U\n#EXT-X-VERSION:7\n"
        #expect(HLSPlaylistParser.parseVariants(playlist: empty, masterURL: masterURL).isEmpty)
    }

    @Test func pinnedQualityPicksTallestAtOrBelowTarget() {
        let stream = makeStream()
        #expect(stream.variant(forMaxHeight: 1080)?.heightPixels == 1080)
        #expect(stream.variant(forMaxHeight: 900)?.heightPixels == 720)
        #expect(stream.variant(forMaxHeight: 2160)?.heightPixels == 1080)
    }

    @Test func pinnedQualityFallsBackToShortestWhenAllAreTaller() {
        let stream = makeStream()
        #expect(stream.variant(forMaxHeight: 480)?.heightPixels == 720)
    }

    @Test func bestVariantIsTheTallest() {
        #expect(makeStream().bestVariant?.heightPixels == 1080)
    }

    private func makeStream() -> HLSStream {
        HLSStream(
            sessionID: "sess-abc",
            masterURL: masterURL,
            authHeaders: ["x-api-key": "k"],
            variants: HLSPlaylistParser.parseVariants(playlist: playlist, masterURL: masterURL)
        )
    }
}
