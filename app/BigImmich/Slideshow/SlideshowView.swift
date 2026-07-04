import AVKit
import ImmichAPI
import SwiftUI

struct SlideshowView: View {
    let initialAlbumID: AlbumID
    let initialAlbumName: AlbumName
    let initialAssetID: AssetID?
    let onExit: (AlbumID, AlbumName, AssetID?) -> Void

    @State private var viewModel: SlideshowViewModel
    @State private var assetDetailsTimer: Timer?

    init(
        initialAlbumID: AlbumID,
        initialAlbumName: AlbumName,
        initialAssetID: AssetID?,
        onExit: @escaping (AlbumID, AlbumName, AssetID?) -> Void
    ) {
        self.initialAlbumID = initialAlbumID
        self.initialAlbumName = initialAlbumName
        self.initialAssetID = initialAssetID
        self.onExit = onExit
        _viewModel = State(
            initialValue: SlideshowViewModel(
                initialAlbumID: initialAlbumID,
                initialAlbumName: initialAlbumName,
                initialAssetID: initialAssetID
            )
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if viewModel.isLoading {
                    ProgressView("Loading...")
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let player = viewModel.currentPlayer {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else if let image = viewModel.currentImage {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                }
            }

            if !viewModel.slideshowIsRunning {
                pausedOverlay
            }

            if viewModel.settings.slideshowShowProgressBar == .always {
                progressBar
            }

            if !viewModel.errors.isEmpty || !viewModel.informations.isEmpty {
                messagesOverlay
            }
        }
        .focusable(true)
        .onAppear {
            Task {
                await viewModel.start()
            }
        }
        .onDisappear {
            viewModel.stop()
        }
        .onExitCommand {
            viewModel.clearImageCache()

            if let asset = viewModel.slideshowAsset {
                onExit(asset.album.id, asset.album.albumName, asset.asset.id)
            } else {
                onExit(initialAlbumID, initialAlbumName, initialAssetID)
            }
        }
        .onMoveCommand { direction in
            Task {
                await viewModel.handleMoveCommand(direction)
            }
        }
        .onPlayPauseCommand {
            viewModel.togglePause()
        }
    }

    private var pausedOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: "pause.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white.opacity(0.9))
                    .padding(20)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .shadow(
                                color: Color.black.opacity(0.6),
                                radius: 6,
                                x: 0,
                                y: 0
                            )
                    )
                    .padding(.leading, 40)

                Spacer()

                if viewModel.showAssetDetails {
                    assetDetails
                }
            }
            .padding(.bottom, 40)
        }
        .transition(.opacity)
    }

    private var assetDetails: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(viewModel.userAssetIndex) / \(viewModel.userAssetsCount)")
                .font(.title2)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)

            if !viewModel.userDateTime.isEmpty {
                Text(viewModel.userDateTime)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.7), radius: 1, x: 0, y: 1)
            }

            if !viewModel.userLocation.isEmpty {
                Text(viewModel.userLocation)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.7), radius: 1, x: 0, y: 1)
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.6))
        .cornerRadius(10)
        .onAppear {
            assetDetailsTimer?.invalidate()
            assetDetailsTimer = Timer.scheduledTimer(
                withTimeInterval: 10,
                repeats: false
            ) { _ in
                withAnimation {
                    viewModel.showAssetDetails = false
                }
            }
        }
        .onDisappear {
            assetDetailsTimer?.invalidate()
            assetDetailsTimer = nil
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.gray.opacity(0.6))
                .frame(
                    width: geometry.size.width * viewModel.assetProgress,
                    height: 4
                )
                .position(
                    x: geometry.size.width / 2,
                    y: geometry.size.height - 2
                )
        }
        .ignoresSafeArea()
    }

    private var messagesOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(Array(viewModel.errors.enumerated()), id: \.offset) { _, error in
                        Text(error)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(10)
                            .shadow(radius: 3)
                    }

                    ForEach(Array(viewModel.informations.enumerated()), id: \.offset) { _, information in
                        Text(information)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.8))
                            .cornerRadius(10)
                            .shadow(radius: 3)
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
        .animation(.easeInOut, value: viewModel.errors)
    }
}
