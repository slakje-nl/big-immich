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
                            isHighlighted: focusedAssetIndex == index,
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
        guard let initialAssetID,
              let index = assets.firstIndex(where: { $0.id == initialAssetID })
        else {
            focusedAssetIndex = 0
            return
        }

        scrollProxy.scrollTo(index, anchor: .center)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedAssetIndex = index
        }
    }

    private func loadAssets() async {
        state = .loading
        do {
            state = try await .loaded(immichClient.getAlbumAssets(albumID: albumID))
        } catch {
            state = .failed(error.localizedDescription)
            logError(error)
        }
    }
}
