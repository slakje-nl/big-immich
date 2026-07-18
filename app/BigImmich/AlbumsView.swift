import ImmichAPI
import Sentry
import SwiftUI

struct AlbumsView: View {
    let initialAlbumID: AlbumID?
    let onSelectAlbum: (AlbumID, AlbumName) -> Void
    var immichClient: ImmichClientProtocol = ImmichClient.shared

    @FocusState private var focusedAlbumIndex: Int?
    @State private var state: LoadingState<[AlbumSummary]> = .idle
    @State private var notYetSetUp = false
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

            if notYetSetUp {
                welcome
            } else {
                switch state {
                case .idle, .loading:
                    ProgressView("Loading albums...")
                        .scaleEffect(1.5)
                        .padding(.top, 50)
                case let .failed(message):
                    Text(message).foregroundColor(.red)
                case let .loaded(albums):
                    grid(albums: albums)
                }
            }
        }
        .task {
            await loadAlbums()
        }
    }

    private var welcome: some View {
        VStack {
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
        }
    }

    private func grid(albums: [AlbumSummary]) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(albums.enumerated()), id: \.offset) { index, album in
                        VStack(spacing: 4) {
                            ThumbnailView(
                                assetID: album.albumThumbnailAssetId,
                                isVideo: false,
                                isHighlighted: focusedAlbumIndex == index,
                                onLoaded: {},
                                onError: { error in
                                    if !(error is CancellationError) {
                                        thumbnailErrors.append(
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
                    focusInitialAlbum(albums: albums, scrollProxy: scrollProxy)
                }
            }
        }
    }

    private func focusInitialAlbum(
        albums: [AlbumSummary],
        scrollProxy: ScrollViewProxy
    ) {
        guard let initialAlbumID,
              let index = albums.firstIndex(where: { $0.id == initialAlbumID })
        else {
            focusedAlbumIndex = 0
            return
        }

        scrollProxy.scrollTo(index, anchor: .center)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedAlbumIndex = index
        }
    }

    private func loadAlbums() async {
        let order: AlbumsOrder = .fromNewest

        // Paint instantly from the previous launch's cache, if any; only show the spinner
        // when we have nothing to show yet. Then refresh in the background below.
        if let cached = AlbumsListCache.shared.cached(order: order) {
            state = .loaded(cached)
        } else {
            state = .loading
        }

        do {
            let albums = try await immichClient.findAlbums(order: order)
            AlbumsListCache.shared.set(order: order, albums: albums)
            // Avoid a needless state churn (and focus/scroll reset) when nothing changed.
            if case let .loaded(current) = state, current == albums {
                return
            }
            state = .loaded(albums)
        } catch ImmichAPIError.missingConfig {
            notYetSetUp = true
        } catch {
            // Keep showing the cached list on a refresh failure; only fail hard with nothing.
            if case .loaded = state {
                logError(error)
            } else {
                state = .failed(error.localizedDescription)
                logError(error)
            }
        }
    }
}
