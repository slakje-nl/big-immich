import ImmichAPI
import Sentry
import SwiftUI

struct AlbumsView: View {
    let initialAlbumID: AlbumID?
    let onSelectAlbum: (AlbumID, AlbumName) -> Void

    @FocusState private var focusedAlbumIndex: Int?
    @State private var albums: [AlbumSummary] = []
    @State private var isLoading = false
    @State private var loadedAssets: Int = 0
    @State private var errors: [String] = []
    @State private var notYetSetUp: Bool = false

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

            if isLoading {
                ProgressView("Loading albums...")
                    .scaleEffect(1.5)
                    .padding(.top, 50)
            } else if notYetSetUp {
                Text("Welcome to Big Immich!").scaleEffect(2)

                Text("It looks like you haven't configured this app yet.")
                    .padding(.top, 50)
                Text(
                    "In order to do that, go to the Settings page and fill in Immich credentials."
                ).padding(.top, 5)

                Text("Little pro tip:").padding(.top, 50)
                Text(
                    "Create a new user just for this app and share selected albums with it."
                ).padding(.top, 5)
                Text(
                    "This way, you will be able to control what is accessible on your tv."
                ).padding(.top, 5)

            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical) {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(Array(albums.enumerated()), id: \.offset) {
                                index,
                                album in
                                VStack(spacing: 4) {
                                    ThumbnailView(
                                        assetID: album.albumThumbnailAssetId,
                                        isVideo: false,
                                        isHighlighted: focusedAlbumIndex
                                            == index,
                                        onLoaded: {},
                                        onError: { error in
                                            if !(error is CancellationError) {
                                                errors.append(
                                                    "Asset \(album.id): \(error.localizedDescription)"
                                                )
                                            }
                                        }
                                    )
                                    .aspectRatio(20 / 9, contentMode: .fill)
                                    .focused($focusedAlbumIndex, equals: index)
                                    .onTapGesture {
                                        onSelectAlbum(album.id, album.albumName)
                                    }
                                    .id(index)

                                    Text(album.albumName.string)
                                        .foregroundColor(.white)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        }
                        .padding(.horizontal, 30)
                        .padding(.vertical, 30)
                        .onAppear {
                            guard let initialAlbumID,
                                let index = albums.firstIndex(where: {
                                    $0.id == initialAlbumID
                                })
                            else {
                                focusedAlbumIndex = 0
                                return
                            }

                            scrollProxy.scrollTo(index, anchor: .center)
                            DispatchQueue.main.asyncAfter(
                                deadline: .now() + 0.1
                            ) {
                                focusedAlbumIndex = index
                            }
                        }
                    }
                }
            }
        }
        .task {
            await loadAlbums()
        }
    }

    private func loadAlbums() async {
        isLoading = true
        do {
            self.albums = try await ImmichClient.shared.findAlbums()
        } catch ImmichAPIError.missingConfig {
            notYetSetUp = true
        } catch {
            errors.append(error.localizedDescription)
            logError(error)
        }
        isLoading = false
    }
}
