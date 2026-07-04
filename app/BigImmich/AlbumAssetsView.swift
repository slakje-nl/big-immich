import ImmichAPI
import Sentry
import SwiftUI

struct AlbumAssetsView: View {
    let albumID: AlbumID
    let initialAssetID: AssetID?
    let startSlideshow: (AssetID) -> Void
    let onExit: () -> Void

    @FocusState private var focusedAssetIndex: Int?
    @State private var album: Album?
    @State private var errors: [String] = []

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 16),
        count: 5
    )

    var body: some View {
        VStack {
            if !errors.isEmpty {
                ForEach(errors, id: \.self) { error in
                    Text(error)
                        .foregroundColor(.red)
                }
            }

            if let album {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(
                                Array(album.assets.enumerated()),
                                id: \.offset
                            ) { index, asset in
                                ThumbnailView(
                                    assetID: asset.id,
                                    isVideo: asset.type == "VIDEO",
                                    isHighlighted: focusedAssetIndex == index,
                                    onLoaded: {},
                                    onError: { error in
                                        errors.append(
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
                            guard let initialAssetID else {
                                focusedAssetIndex = 0
                                return
                            }

                            if let index = album.assets.firstIndex(where: {
                                $0.id == initialAssetID
                            }) {
                                scrollProxy.scrollTo(index, anchor: .center)
                                DispatchQueue.main.asyncAfter(
                                    deadline: .now() + 0.1
                                ) {
                                    focusedAssetIndex = index
                                }
                            } else {
                                focusedAssetIndex = 0
                            }
                        }
                    }
                }
            }
        }
        .task {
            await loadAlbumDetail()
        }
        .onExitCommand(perform: onExit)
    }

    private func loadAlbumDetail() async {
        do {
            album = try await ImmichAPI.shared.loadObject(
                path: "/api/albums/\(albumID.string)",
                queryParams: [:]
            )
        } catch {
            errors.append(error.localizedDescription)
            logError(error)
        }
    }
}
