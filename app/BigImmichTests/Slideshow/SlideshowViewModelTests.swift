@testable import BigImmich
import ImmichAPI
import Testing

@MainActor
struct SlideshowViewModelTests {
    private func makeViewModel(recording calls: @escaping @MainActor (Bool) -> Void) -> SlideshowViewModel {
        let albumID = AlbumID(rawValue: "album.1")
        let client = FakeImmichClient(
            albumSummaries: [AlbumSummary.dummy(id: albumID.string)],
            albumAssets: [albumID: [AlbumAsset.dummy(id: "asset.1")]]
        )
        return SlideshowViewModel(
            initialAlbumID: albumID,
            initialAlbumName: AlbumName(rawValue: "album name"),
            initialAssetID: nil,
            immichClient: client,
            setIdleTimerDisabled: calls
        )
    }

    @Test func startKeepsScreenAwakeAndStopRestoresIt() async {
        final class Recorder { var values: [Bool] = [] }
        let recorder = Recorder()
        let viewModel = makeViewModel { recorder.values.append($0) }

        await viewModel.start()
        #expect(recorder.values == [true])

        viewModel.stop()
        #expect(recorder.values == [true, false])
    }
}
