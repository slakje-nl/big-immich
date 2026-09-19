@testable import BigImmich
import Foundation
import ImmichAPI
import Testing

@MainActor
struct SlideshowViewModelTests {
    private func makeViewModel(recording calls: @escaping @MainActor (Bool) -> Void) -> SlideshowViewModel {
        // Unique per run: the view model goes through the shared on-disk asset cache, so a fixed
        // id would leak this test's assets into other tests that use the same album id.
        let albumID = AlbumID(rawValue: "view-model-test-\(UUID().uuidString)")
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
