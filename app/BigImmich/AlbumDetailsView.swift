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

    @FocusState private var focusedButton: ButtonFocus?
    @State private var album: Album?
    @State private var assets: [AlbumAsset] = []
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

    func getItemsCount() -> String {
        let images = assets.count(where: { $0.assetType == .image })
        let videos = assets.count(where: { $0.assetType == .video })

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
        guard album != nil else { return "" }

        let duration = slideshowDurationMinutes(
            items: assets,
            imageInterval: slideshowInterval
        )
        if duration == 1 {
            return "\(duration) minute"
        }

        return "\(duration) minutes"
    }

    private func loadAlbumDetail() async {
        isLoading = true
        do {
            album = try await ImmichAPI.shared.loadObject(
                path: "/api/albums/\(albumID.string)",
                queryParams: [:]
            )
            assets = try await ImmichClient.shared.getAlbumAssets(albumID: albumID)

            if let thumbnailAssetId = album?.albumThumbnailAssetId {
                let data = try await ImmichAPI.shared.loadMediaWithRetries(
                    path:
                    "/api/assets/\(thumbnailAssetId.string)/thumbnail",
                    queryParams: ["size": "preview"],
                    retries: 3
                )
                if let uiImage = UIImage(data: data) {
                    thumbnailImage = Image(uiImage: uiImage)
                } else {
                    errors.append("thumbnail couldn't get loaded into UIImage")
                }
            }
        } catch {
            errors.append(error.localizedDescription)
            logError(error)
        }
        isLoading = false
    }
}
