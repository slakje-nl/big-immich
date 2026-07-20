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
    /// A mid-stream rebuffer only surfaces the "Buffering…" overlay once it has lasted past a short
    /// grace window, so brief stalls don't flash it on and off.
    @State private var showBufferingOverlay = false

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
                    PlayerLayerView(player: player)
                        .ignoresSafeArea()
                        .overlay {
                            videoBufferingOverlay
                        }
                } else if let image = viewModel.currentImage {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                }
            }

            if !viewModel.slideshowIsRunning, !viewModel.showOptionsMenu {
                pausedOverlay
            }

            // The options overlay pauses playback; a small pause badge shows it's paused,
            // without the full paused overlay's asset details.
            if viewModel.showOptionsMenu, viewModel.currentImage != nil {
                imagePausedBadge
            }

            if viewModel.showVideoScrubber {
                videoScrubber
            }

            if viewModel.settings.slideshowShowProgressBar == .always {
                progressBar
            }

            if viewModel.showVideoStats, viewModel.currentPlayer != nil {
                videoStatsOverlay
            }

            if viewModel.showVideoStats, viewModel.currentImage != nil {
                photoStatsOverlay
            }

            if viewModel.showOptionsMenu {
                optionsMenuOverlay
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
            // The options overlay swallows the back button to close itself, not the slideshow.
            if viewModel.showOptionsMenu {
                viewModel.closeOptionsMenu()
                return
            }

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
        .onTapGesture {
            viewModel.handleSelect()
        }
    }

    private var pausedOverlay: some View {
        // In video mode the scrubber (video progress bar) sits at the bottom, so drop the pause
        // icon and lift the asset number to sit just above the scrubber.
        let isVideo = viewModel.currentPlayer != nil
        return VStack {
            Spacer()
            HStack {
                if !isVideo {
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
                }

                Spacer()

                if viewModel.showAssetDetails {
                    // Line the box's right edge up with the scrubber (same 60pt inset).
                    assetDetails
                        .padding(.trailing, isVideo ? 60 : 0)
                }
            }
            .padding(.bottom, isVideo ? 170 : 40)
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
                // Scheduled on the main run loop, so the callback runs on the main actor.
                MainActor.assumeIsolated {
                    withAnimation {
                        viewModel.showAssetDetails = false
                    }
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

    /// Spinner shown while the video is loading its first data or rebuffering mid-stream.
    /// "Buffering…" tells the viewer we're waiting on the network, not stuck — but only after a
    /// mid-stream rebuffer has persisted past a short grace window, so brief stalls don't flash it.
    private var videoBufferingOverlay: some View {
        ZStack {
            if viewModel.videoState == .loading {
                ProgressView().scaleEffect(1.5)
            } else if viewModel.videoState == .buffering, showBufferingOverlay {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Buffering…")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.8), radius: 2)
                }
            }
        }
        .task(id: viewModel.videoState) {
            guard viewModel.videoState == .buffering else {
                showBufferingOverlay = false
                return
            }
            showBufferingOverlay = false
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            showBufferingOverlay = true
        }
    }

    /// The video progress bar. It shows a pause indicator while paused, and always shows what
    /// left/right will do: scrub ±N seconds while paused mid-video, or change to the prev/next
    /// asset at the very start/end — or, while playing (a down-button peek), asset changes too,
    /// since left/right move between assets then.
    private var videoScrubber: some View {
        // The bar only shows when left/right scrub (paused, or a peek) — so hints are scrub unless
        // at the very start/end, where they flip to the configured prev/next-asset action.
        let paused = !viewModel.slideshowIsRunning
        let step = viewModel.videoScrubStepSeconds
        let leftHint = viewModel.videoAtStart ? "‹ \(assetActionLabel(viewModel.settings.slideshowLeftAction))" : "‹ \(step)s"
        let rightHint = viewModel.videoAtEnd ? "\(assetActionLabel(viewModel.settings.slideshowRightAction)) ›" : "\(step)s ›"
        return VStack {
            Spacer()
            VStack(spacing: 8) {
                HStack {
                    Text(leftHint)
                    Spacer()
                    Text(rightHint)
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.25))
                            .frame(height: 6)
                        Capsule()
                            .fill(Color.white)
                            .frame(
                                width: geometry.size.width * viewModel.assetProgress,
                                height: 6
                            )
                    }
                }
                .frame(height: 6)

                HStack(spacing: 8) {
                    if paused {
                        Image(systemName: "pause.fill")
                    }
                    Text(SlideshowView.timeLabel(viewModel.videoDisplaySeconds))
                    Spacer()
                    Text(SlideshowView.timeLabel(viewModel.videoDurationSeconds))
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 80)
        }
        .transition(.opacity)
    }

    /// The optional "nerd stats" overlay: live bitrate, resolution, buffer and stall counters.
    private var videoStatsOverlay: some View {
        let stats = viewModel.videoStats
        return VStack(alignment: .leading, spacing: 4) {
            if stats.resolution != .zero {
                statLine("Resolution", "\(Int(stats.resolution.width))×\(Int(stats.resolution.height))")
            }
            if !stats.codec.isEmpty {
                statLine("Codec", stats.codec)
            }
            if stats.frameRate > 0 {
                statLine("Frame rate", String(format: "%.0f fps", stats.frameRate))
            }
            if !stats.colorSpace.isEmpty {
                statLine("Colour", stats.colorSpace)
            }
            statLine("Bitrate", SlideshowView.bitrateLabel(stats.indicatedBitrate))
            statLine("Observed", SlideshowView.bitrateLabel(stats.observedBitrate))
            statLine("Buffer", String(format: "%.1fs", stats.bufferedAhead))
            statLine("Stalls", "\(stats.stalls)")
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundColor(.green)
        .padding(12)
        .background(Color.black.opacity(0.55))
        .cornerRadius(8)
        .padding(.top, 40)
        .padding(.leading, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A small pause badge shown while the options overlay is open over a photo.
    private var imagePausedBadge: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: "pause.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white.opacity(0.9))
                    .padding(20)
                    .background(Circle().fill(Color.black.opacity(0.4)))
                    .padding(.leading, 40)
                Spacer()
            }
            .padding(.bottom, 40)
        }
    }

    /// The optional "nerd stats" overlay for photos: file name, dimensions and size, from the
    /// full asset's EXIF (fetched into `detailedAsset`, since the search EXIF is partial).
    private var photoStatsOverlay: some View {
        let asset = viewModel.detailedAsset ?? viewModel.slideshowAsset?.asset
        let exif = asset?.exifInfo
        return VStack(alignment: .leading, spacing: 4) {
            if let name = asset?.originalFileName, !name.isEmpty {
                statLine("File", name)
            }
            if let width = exif?.exifImageWidth, let height = exif?.exifImageHeight {
                statLine("Dimensions", "\(width) × \(height)")
            }
            if let bytes = exif?.fileSizeInByte {
                statLine("Size", ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
            }
            if asset == nil || (asset?.originalFileName == nil && exif?.exifImageWidth == nil) {
                statLine("Metadata", "loading…")
            }
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundColor(.green)
        .padding(12)
        .background(Color.black.opacity(0.55))
        .cornerRadius(8)
        .padding(.top, 40)
        .padding(.leading, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The in-slideshow options overlay (up button). A card anchored to the right so the
    /// slideshow stays visible behind it. Photos show the interval + nerd stats; videos show
    /// nerd stats. Up/down navigate rows, left/right adjust the interval, select flips a toggle.
    private var optionsMenuOverlay: some View {
        HStack {
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.currentPlayer != nil ? "Video options" : "Slideshow")
                    .font(.title3).bold()
                    .foregroundColor(.white)
                    .padding(.bottom, 12)

                ForEach(Array(viewModel.optionsMenuItems.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 16) {
                        optionRowLabel(row).foregroundColor(.white)
                        Spacer(minLength: 24)
                        optionRowValue(row)
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        index == viewModel.optionsMenuIndex
                            ? Color.white.opacity(0.22) : Color.clear
                    )
                    .cornerRadius(8)
                }

                Text("◀ Back")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 14)
                    .padding(.horizontal, 20)
            }
            .padding(32)
            .frame(width: 480)
            .background(.black.opacity(0.82))
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.5), radius: 20)
            .padding(.trailing, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func optionRowLabel(_ row: SlideshowViewModel.OptionRow) -> Text {
        switch row {
        case .interval: Text("Slideshow interval")
        case .toggleStats: Text("Nerd stats")
        }
    }

    /// The current value of an options row, read from the observable mirrors so it updates live.
    /// The interval is flanked by ‹ › to show it's adjusted with left/right; nerd stats is a
    /// switch flipped with the select button.
    @ViewBuilder
    private func optionRowValue(_ row: SlideshowViewModel.OptionRow) -> some View {
        switch row {
        case .interval:
            // Hide the chevron once the value can't move that way, but keep it occupying its space
            // (opacity, not removal) so the number stays put.
            HStack(spacing: 12) {
                Text("‹").foregroundColor(.white.opacity(viewModel.displayInterval <= 1 ? 0 : 0.4))
                Text("\(viewModel.displayInterval)s").foregroundColor(.white.opacity(0.85))
                Text("›").foregroundColor(.white.opacity(viewModel.displayInterval >= 60 ? 0 : 0.4))
            }
        case .toggleStats:
            Capsule()
                .fill(viewModel.showVideoStats ? Color.green : Color.white.opacity(0.25))
                .frame(width: 50, height: 28)
                .overlay(
                    Circle().fill(.white).padding(3),
                    alignment: viewModel.showVideoStats ? .trailing : .leading
                )
        }
    }

    private func statLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundColor(.green.opacity(0.6))
            Text(value)
        }
    }

    /// What a left/right press moves to, for the scrubber hints.
    private func assetActionLabel(_ action: SlideshowAction) -> String {
        action == .goToNext ? "Next asset" : "Previous asset"
    }

    /// Formats seconds as `m:ss` (or `h:mm:ss`) for the scrubber.
    static func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let secs = total % 60
        let mins = (total / 60) % 60
        let hours = total / 3600
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, mins, secs)
            : String(format: "%d:%02d", mins, secs)
    }

    /// Formats a bits/second value as Mbps/kbps for the stats overlay.
    static func bitrateLabel(_ bitsPerSecond: Double) -> String {
        guard bitsPerSecond > 0 else { return "—" }
        if bitsPerSecond >= 1_000_000 {
            return String(format: "%.1f Mbps", bitsPerSecond / 1_000_000)
        }
        return String(format: "%.0f kbps", bitsPerSecond / 1000)
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
