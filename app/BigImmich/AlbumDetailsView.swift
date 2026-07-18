import ImmichAPI
import Sentry
import SwiftUI

enum ButtonFocus: Hashable {
    case slideshow
    case viewAssets
}

struct AlbumDetailsView: View {
    let albumID: AlbumID
    let initialyFocusedButton: ButtonFocus
    let startSlideshow: () -> Void
    let viewAssets: () -> Void
    let onExit: () -> Void
    var immichClient: ImmichClientProtocol = ImmichClient.shared

    @FocusState private var focusedButton: ButtonFocus?
    @State private var album: Album?
    @State private var assets: [AlbumAsset]?
    @State private var thumbnailImage: Image?
    @State private var isLoading = true
    @State private var errors: [String] = []

    @AppStorage("slideshowInterval") private var slideshowInterval: Int = 5

    var body: some View {
        GeometryReader { geo in
            VStack {
                if !errors.isEmpty {
                    ForEach(errors, id: \.self) { error in
                        Text(error)
                            .foregroundColor(.red)
                    }
                }

                if isLoading {
                    ProgressView("Loading album...")
                        .scaleEffect(1.5)
                        .padding(.top, 50)
                } else {
                    if let album {
                        Spacer()

                        HStack(alignment: .top, spacing: 20) {
                            // left side: album thumbnail
                            if let thumbnailImage {
                                thumbnailImage
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: geo.size.width * 0.8 * 0.4)
                                    .cornerRadius(12)
                                    .shadow(radius: 5)
                            } else {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(
                                        width: geo.size.width * 0.8 * 0.4,
                                        height: geo.size.width * 0.8 * 0.4
                                    )
                                    .cornerRadius(12)
                                    .overlay(ProgressView())
                            }

                            Spacer()

                            // right side: album details, buttons
                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 20) {
                                    Text(album.albumName.string)
                                        .font(.title2)
                                        .fontWeight(.bold)

                                    Text("Items: \(getItemsCount())")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(.bottom, 30)

                                    Button(action: startSlideshow) {
                                        Label(
                                            "Slideshow (\(getSlideshowDurationText()))",
                                            systemImage: "play.circle"
                                        )
                                        .padding(20)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }.focused(
                                        $focusedButton,
                                        equals: .slideshow
                                    )
                                    .accessibilityIdentifier("startSlideshowButton")

                                    Button(action: viewAssets) {
                                        Label(
                                            "View assets",
                                            systemImage: "photo.on.rectangle"
                                        )
                                        .padding(20)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.green)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }.focused(
                                        $focusedButton,
                                        equals: .viewAssets
                                    )
                                    .accessibilityIdentifier("viewAssetsButton")
                                }
                            }
                            .frame(
                                maxWidth: geo.size.width * 0.8 * 0.6,
                                alignment: .top
                            )
                            .padding()
                        }
                        .frame(width: geo.size.width * 0.8, alignment: .top)
                        .padding()

                        Spacer()
                    }
                }
            }
            .frame(
                width: geo.size.width,
                height: geo.size.height,
                alignment: .top
            )
        }
        .task {
            await loadAlbumDetail()
            focusedButton = initialyFocusedButton
        }
        .onExitCommand(perform: onExit)
    }

    private var imageCount: Int {
        assets?.count(where: { $0.assetType == .image }) ?? 0
    }

    private var videoCount: Int {
        assets?.count(where: { $0.assetType == .video }) ?? 0
    }

    private var videoDurationMs: Int {
        (assets ?? [])
            .filter { $0.assetType == .video }
            .reduce(0) { $0 + ($1.durationMilliseconds ?? 0) }
    }

    func getItemsCount() -> String {
        let images = imageCount
        let videos = videoCount

        var imagesLabel = ""
        if images > 1 {
            imagesLabel = "\(images) images"
        } else if images == 1 {
            imagesLabel = "\(images) image"
        }

        var videosLabel = ""
        if videos > 1 {
            videosLabel = "\(videos) videos"
        } else if videos == 1 {
            videosLabel = "\(videos) video"
        }

        if !imagesLabel.isEmpty, !videosLabel.isEmpty {
            return "\(imagesLabel) and \(videosLabel)"
        } else if !imagesLabel.isEmpty {
            return imagesLabel
        } else if !videosLabel.isEmpty {
            return videosLabel
        }

        return "no items"
    }

    private func getSlideshowDurationText() -> String {
        guard assets != nil else { return "" }

        let duration = slideshowDurationMinutes(
            imageCount: imageCount,
            videoDurationMilliseconds: videoDurationMs,
            imageInterval: slideshowInterval
        )
        if duration == 1 {
            return "\(duration) minute"
        }

        return "\(duration) minutes"
    }

    private func loadAlbumDetail() async {
        isLoading = true

        // Paint instantly from the previous visit's disk caches, if any, then refresh below.
        // Albums change rarely, so the cached header and asset list are almost always still
        // correct; a brand-new album shows the spinner until its list loads.
        if let cachedAlbum = AlbumDetailCache.shared.cached(albumID: albumID) {
            album = cachedAlbum
        }
        if let cachedAssets = AlbumAssetsCache.shared.cached(albumID: albumID) {
            assets = cachedAssets
        }
        if album != nil, assets != nil {
            isLoading = false
        }

        do {
            // The album header and its asset list are independent — fetch concurrently. The
            // item counts and duration are derived from the full asset list, which the
            // slideshow and asset grid cache too, so this visit warms them all at once.
            async let albumTask = immichClient.getAlbum(albumID: albumID)
            async let assetsTask = immichClient.getAlbumAssets(albumID: albumID)

            let loadedAlbum = try await albumTask
            album = loadedAlbum
            AlbumDetailCache.shared.set(loadedAlbum)

            async let thumbnailTask = fetchThumbnail(for: loadedAlbum)

            let loadedAssets = try await assetsTask
            assets = loadedAssets
            AlbumAssetsCache.shared.set(albumID: albumID, assets: loadedAssets)

            thumbnailImage = try await thumbnailTask
        } catch {
            // Only surface the error if we had nothing cached to fall back on.
            if assets == nil {
                errors.append(error.localizedDescription)
            }
            logError(error)
        }
        isLoading = false
    }

    private func fetchThumbnail(for album: Album) async throws -> Image? {
        guard let thumbnailAssetId = album.albumThumbnailAssetId else { return nil }
        return try await AssetImageLoader(immichClient: immichClient)
            .load(assetID: thumbnailAssetId, size: .preview, retries: 3)
    }
}
