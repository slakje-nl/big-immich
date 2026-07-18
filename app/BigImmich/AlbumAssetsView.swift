import ImmichAPI
import Sentry
import SwiftUI

struct AlbumAssetsView: View {
    let albumID: AlbumID
    let initialAssetID: AssetID?
    let startSlideshow: (AssetID) -> Void
    let onExit: () -> Void
    var immichClient: ImmichClientProtocol = ImmichClient.shared

    @FocusState private var focusedAssetIndex: Int?
    @State private var focusRestored = false
    @State private var state: LoadingState<[AlbumAsset]> = .idle
    @State private var thumbnailErrors: [String] = []

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 16),
        count: 5
    )

    var body: some View {
        VStack {
            ForEach(thumbnailErrors, id: \.self) { error in
                Text(error).foregroundColor(.red)
            }

            switch state {
            case .idle, .loading:
                EmptyView()
            case let .failed(message):
                Text(message).foregroundColor(.red)
            case let .loaded(assets):
                grid(assets: assets)
            }
        }
        .task {
            await loadAssets()
        }
        .onExitCommand(perform: onExit)
    }

    private func grid(assets: [AlbumAsset]) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(assets.enumerated()), id: \.offset) { index, asset in
                        ThumbnailView(
                            assetID: asset.id,
                            isVideo: asset.assetType == .video,
                            isHighlighted: focusRestored && focusedAssetIndex == index,
                            onLoaded: {},
                            onError: { error in
                                thumbnailErrors.append(
                                    "Asset \(asset.id): \(error.localizedDescription)"
                                )
                                logError(error)
                            }
                        )
                        .aspectRatio(20 / 9, contentMode: .fit)
                        .focused($focusedAssetIndex, equals: index)
                        .onTapGesture {
                            startSlideshow(asset.id)
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
                .onAppear {
                    focusInitialAsset(assets: assets, scrollProxy: scrollProxy)
                }
            }
        }
    }

    private func focusInitialAsset(
        assets: [AlbumAsset],
        scrollProxy: ScrollViewProxy
    ) {
        let index = initialAssetID
            .flatMap { id in assets.firstIndex(where: { $0.id == id }) } ?? 0
        // The target cell may not be materialized yet in the lazy grid, so scroll to it
        // first and set focus a beat later. Until that restore lands we suppress the
        // custom highlight (focusRestored) so the grid doesn't briefly light up the first
        // cell that the focus engine parks on in the meantime. Reset the flag every time
        // this runs — on back-navigation the @State is preserved and would otherwise stay
        // true, letting the transient item-0 focus show through.
        focusRestored = false
        scrollProxy.scrollTo(index, anchor: .center)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedAssetIndex = index
            focusRestored = true
        }
    }

    private func loadAssets() async {
        // Paint instantly from the previous visit's cache; only spin when we have nothing.
        if let cached = AlbumAssetsCache.shared.cached(albumID: albumID) {
            state = .loaded(cached)
        } else {
            state = .loading
        }

        do {
            let assets = try await immichClient.getAlbumAssets(albumID: albumID)
            AlbumAssetsCache.shared.set(albumID: albumID, assets: assets)
            // Skip the re-render (and focus/scroll reset) when the asset set is unchanged.
            if case let .loaded(current) = state, current.map(\.id) == assets.map(\.id) {
                return
            }
            state = .loaded(assets)
        } catch {
            // Keep the cached grid on a refresh failure; only fail hard with nothing to show.
            if case .loaded = state {
                logError(error)
            } else {
                state = .failed(error.localizedDescription)
                logError(error)
            }
        }
    }
}
