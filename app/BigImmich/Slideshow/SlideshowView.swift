import AVKit
import ImmichAPI
import Sentry
import SwiftUI

struct SlideshowView: View {
    let initialAlbumID: AlbumID
    let initialAlbumName: AlbumName
    let initialAssetID: AssetID?
    let onExit: (AlbumID, AlbumName, AssetID?) -> Void

    @State private var slideshow: SlideshowSequencer? = nil
    @State private var slideshowAsset: SlideshowAsset? = nil
    @State private var previousAlbumID: AlbumID? = nil

    // showing details of an image (when paused)
    @State private var userAssetIndex: Int = 0
    @State private var userAssetsCount: Int = 0
    @State private var userDateTime: String = ""
    @State private var userLocation: String = ""

    // current image / player in the slideshow
    @State private var currentImage: Image? = nil
    @State private var currentPlayer: AVPlayer? = nil
    @State private var playerObserver: NSObjectProtocol? = nil
    @State private var playerIsVisible: Bool = false

    // loading assets and error reporting
    @State private var isLoading = false
    @State private var errors: [String] = []
    @State private var clearErrors: DispatchWorkItem?
    @State private var informations: [String] = []

    // loading settings
    @State private var settings: SlideshowSettings = SlideshowSettings()

    // slideshow + overlays
    @State private var slideshowTimer: Timer? = nil
    @State private var slideshowIsRunning = true
    @State private var showAssetDetails = false
    @State private var assetDetailsTimer: Timer? = nil

    // progress bar
    @State private var assetProgress: Double = 0.0
    @State private var progressBarTimer: Timer? = nil

    // preloading assets
    @State private var imageCache: MemoryCache<AssetID, Image>? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if isLoading {
                    ProgressView("Loading...")
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let player = currentPlayer {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                        .onAppear {
                            playerIsVisible = true
                            player.play()
                        }
                        .onDisappear {
                            playerIsVisible = false
                        }
                } else if let image = currentImage {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                }
            }

            if !slideshowIsRunning {
                VStack {
                    Spacer()
                    HStack {
                        // pause icon on the bottom left
                        Image(systemName: "pause.fill")
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(20)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.4))  // semi-transparent background
                                    .shadow(
                                        color: Color.black.opacity(0.6),
                                        radius: 6,
                                        x: 0,
                                        y: 0
                                    )  // round shadow
                            )
                            .padding(.leading, 40)

                        Spacer()

                        // exif and stuff on the bottom right
                        if showAssetDetails {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\(userAssetIndex) / \(userAssetsCount)")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .shadow(
                                        color: .black.opacity(0.8),
                                        radius: 2,
                                        x: 0,
                                        y: 1
                                    )

                                if !(userDateTime.isEmpty) {
                                    Text("\(userDateTime)")
                                        .font(.headline)
                                        .foregroundColor(.white.opacity(0.9))
                                        .shadow(
                                            color: .black.opacity(0.7),
                                            radius: 1,
                                            x: 0,
                                            y: 1
                                        )
                                }

                                if !(userLocation.isEmpty) {
                                    Text("\(userLocation)")
                                        .font(.headline)
                                        .foregroundColor(.white.opacity(0.9))
                                        .shadow(
                                            color: .black.opacity(0.7),
                                            radius: 1,
                                            x: 0,
                                            y: 1
                                        )
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
                                        showAssetDetails = false
                                    }
                                }
                            }
                            .onDisappear {
                                assetDetailsTimer?.invalidate()
                                assetDetailsTimer = nil
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
                .transition(.opacity)
            }

            // progress bar
            if settings.slideshowShowProgressBar == .always {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.gray.opacity(0.6))
                        .frame(
                            width: geometry.size.width * assetProgress,
                            height: 4
                        )
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height - 2
                        )
                }
                .ignoresSafeArea()
            }

            // errors and informations overlay
            if !errors.isEmpty || !informations.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            ForEach(errors.indices, id: \.self) { index in
                                Text(errors[index])
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.red.opacity(0.8))
                                    .cornerRadius(10)
                                    .shadow(radius: 3)
                            }

                            ForEach(informations.indices, id: \.self) { index in
                                Text(informations[index])
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
                .animation(.easeInOut, value: errors)
            }
        }
        .focusable(true)
        .onAppear {
            Task {
                imageCache = MemoryCache(countLimit: 10, megaBytesLimit: nil)
                await initSlideshow(albumID: initialAlbumID)
            }
        }
        .onDisappear {
            stopSlideshowTimer()
            stopProgressBarTimer()
            stopCurrentPlayer()
        }
        .onExitCommand {
            imageCache?.clear()

            Task {
                if let slideshow = slideshow,
                    let slideshowAsset = try? await slideshow.current()
                {
                    onExit(
                        slideshowAsset.album.id,
                        slideshowAsset.album.albumName,
                        slideshowAsset.asset.id
                    )
                } else {
                    onExit(initialAlbumID, initialAlbumName, initialAssetID)
                }
            }
        }
        .onMoveCommand { direction in
            Task {
                await handleMoveCommand(direction)
            }
        }
        .onPlayPauseCommand {
            togglePause()
        }
    }

    func showError(_ message: String) {
        withAnimation {
            errors.append(message)
        }

        clearErrors?.cancel()

        let workItem = DispatchWorkItem {
            withAnimation {
                errors.removeAll()
            }
        }
        clearErrors = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: workItem)
    }

    func showInformation(_ message: String) {
        withAnimation {
            informations.append(message)
        }
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) async {
        switch direction {
        case .left:
            stopSlideshowTimer()
            stopProgressBarTimer()

            switch settings.slideshowLeftAction {
            case .goToNext:
                await moveToNext()
            case .goToPrevious:
                await moveToPrevious()
            }
        case .right:
            stopSlideshowTimer()
            stopProgressBarTimer()

            switch settings.slideshowRightAction {
            case .goToNext:
                await moveToNext()
            case .goToPrevious:
                await moveToPrevious()
            }
        case .up:
            if let player = currentPlayer {
                seek(player: player, seconds: 15)
            }
        case .down:
            if let player = currentPlayer {
                seek(player: player, seconds: -15)
            }
        default:
            break
        }
    }

    private func seek(player: AVPlayer, seconds: Double) {
        guard let currentItem = player.currentItem else { return }
        let currentTime = player.currentTime()
        let newTime = CMTimeAdd(
            currentTime,
            CMTimeMakeWithSeconds(
                seconds,
                preferredTimescale: currentTime.timescale
            )
        )

        let clampedTime: CMTime
        if CMTimeCompare(newTime, .zero) < 0 {
            clampedTime = .zero
        } else if CMTimeCompare(newTime, currentItem.duration) > 0 {
            return
        } else {
            clampedTime = newTime
        }

        player.seek(to: clampedTime)
    }

    private func togglePause() {
        if let player = currentPlayer {
            let isPlaying =
                player.timeControlStatus == .playing && player.rate != 0

            if isPlaying {
                player.pause()
            } else {
                player.play()
                observeVideoProgress()
            }
        } else if currentImage != nil {
            withAnimation {
                slideshowIsRunning.toggle()
            }

            if slideshowIsRunning {
                startImageTimers()
            } else {
                showAssetDetails = true
                stopSlideshowTimer()
                stopProgressBarTimer()
            }
        }
    }

    private func formatDate(asset: AlbumAsset) -> String {
        guard let exifInfo = asset.exifInfo else { return "" }
        guard let original = exifInfo.dateTimeOriginal else { return "" }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime, .withFractionalSeconds,
        ]

        guard let date = formatter.date(from: original) else {
            return ""
        }

        let europeanFormatter = DateFormatter()
        europeanFormatter.dateFormat = "dd/MM/yyyy HH:mm"

        return europeanFormatter.string(from: date)
    }

    private func formatLocation(asset: AlbumAsset) -> String {
        guard let exifInfo = asset.exifInfo else { return "" }
        guard let city = exifInfo.city else { return "" }
        guard let state = exifInfo.state else { return "" }
        guard let country = exifInfo.country else { return "" }

        return city + ", " + state + ", " + country
    }

    private func loadCurrentAsset(slideshowAsset: SlideshowAsset) async {
        // stop actions
        stopSlideshowTimer()
        stopProgressBarTimer()
        stopCurrentPlayer()

        let asset = slideshowAsset.asset
        self.slideshowAsset = slideshowAsset

        if previousAlbumID == nil {
            previousAlbumID = slideshowAsset.album.id
        }
        withAnimation {
            informations.removeAll()
        }

        // clear state
        currentImage = nil
        currentPlayer = nil
        assetProgress = 0.0

        userAssetIndex = slideshowAsset.counter.current
        userAssetsCount = slideshowAsset.counter.total
        userDateTime = formatDate(asset: asset)
        userLocation = formatLocation(asset: asset)

        do {
            if asset.type.uppercased() == "IMAGE" {
                if let cache = imageCache, let nextImage = cache.get(asset.id) {
                    currentImage = nextImage
                } else {
                    let data = try await ImmichAPI.shared.loadMediaWithRetries(
                        path:
                            "/api/assets/\(slideshowAsset.asset.id.string)/thumbnail",
                        queryParams: ["size": "fullsize"],
                        retries: 3,
                    )
                    if let uiImage = UIImage(data: data) {
                        currentImage = Image(uiImage: uiImage)
                    } else {
                        showError("loading image failed: id=\(asset.id)")
                        await self.moveToNext()
                        return
                    }
                }

                if slideshowIsRunning {
                    startImageTimers()
                }
            } else if asset.type.uppercased() == "VIDEO" {
                var playbackURL: URL
                do {
                    playbackURL = try await ImmichAPI.shared
                        .getUrlWithQueryAuth(
                            path:
                                "/api/assets/\(asset.id.string)/video/playback",
                            queryParams: nil
                        )
                } catch {
                    showError(
                        "loading video failed: failed to construct playback URL"
                    )
                    return
                }

                let playerItem = AVPlayerItem(url: playbackURL)
                let player = AVPlayer(playerItem: playerItem)
                currentPlayer = player

                let oldAssetID = asset.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    [oldAssetID] in
                    // monitoring if video is started and playing in 5s
                    // there's no reason for 5s, it just sounds like a good amount of time
                    // FIXME: this is sometimes flaky, I'm not yet sure why
                    guard let player = self.currentPlayer else { return }
                    guard let sAsset = self.slideshowAsset,
                        sAsset.asset.id == oldAssetID
                    else { return }

                    if player.status == .failed
                        || player.currentItem?.status == .failed
                    {
                        self.showError("video failed to load")
                        Task {
                            await self.moveToNext()
                        }
                        return
                    } else if player.timeControlStatus != .playing {
                        self.showError("video did not start playing")
                        Task {
                            await self.moveToNext()
                        }
                        return
                    }
                }

                observeVideoProgress()

                if let playerObserver {
                    NotificationCenter.default.removeObserver(playerObserver)
                }

                if let currentPlayer {
                    playerObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: currentPlayer.currentItem,
                        queue: .main
                    ) { _ in
                        Task {
                            await moveToNext()
                        }
                    }
                }
            }
        } catch {
            showError(error.localizedDescription)
            logError(error)
            isLoading = false
            await moveToNext()
            return
        }

        if previousAlbumID != slideshowAsset.album.id {
            previousAlbumID = slideshowAsset.album.id
            showInformation(
                "switched to a new album: \(slideshowAsset.album.albumName.string)"
            )
        }

        await preloadAssets()
    }

    private func preloadAssets() async {
        guard let slideshow else { return }

        if let laterAsset = try? await slideshow.previewNext() {
            await preloadAsset(
                asset: laterAsset.asset,
            )
        }
        if let earlierAsset = try? await slideshow.previewPrevious() {
            await preloadAsset(
                asset: earlierAsset.asset,
            )
        }
    }

    private func preloadAsset(asset: AlbumAsset) async {
        if let cache = imageCache, asset.type.uppercased() == "IMAGE" {
            guard cache.get(asset.id) == nil else { return }

            do {
                let data = try await ImmichAPI.shared.loadMediaWithRetries(
                    path: "/api/assets/\(asset.id.string)/thumbnail",
                    queryParams: ["size": "fullsize"],
                    retries: 2
                )
                if let uiImage = UIImage(data: data) {
                    cache.set(asset.id, value: Image(uiImage: uiImage))
                }
            } catch {
                logError(error)
                return
            }
        }

        // TODO: add preloading videos, removed since it was too flaky
        // it must be run in a background thread, it was messing up progress bar otherwise
    }

    private func startImageTimers() {
        stopSlideshowTimer()
        stopProgressBarTimer()
        assetProgress = 0.0

        let step = 0.05
        let totalSteps = Double(settings.slideshowInterval) / step
        progressBarTimer = Timer.scheduledTimer(
            withTimeInterval: step,
            repeats: true
        ) { t in
            assetProgress += 1 / totalSteps
            if assetProgress >= 1 {
                t.invalidate()
            }
        }

        slideshowTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(settings.slideshowInterval),
            repeats: false
        ) { _ in
            Task {
                await moveToNext()
            }
        }
    }

    private func stopSlideshowTimer() {
        slideshowTimer?.invalidate()
        slideshowTimer = nil
    }

    private func stopProgressBarTimer() {
        progressBarTimer?.invalidate()
        progressBarTimer = nil
    }

    private func observeVideoProgress() {
        stopProgressBarTimer()
        guard let player = currentPlayer else { return }

        let interval = CMTime(
            seconds: 0.05,
            preferredTimescale: CMTimeScale(NSEC_PER_SEC)
        )
        player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            time in
            if let duration = player.currentItem?.duration.seconds, duration > 0
            {
                assetProgress = min(time.seconds / duration, 1.0)
            }
        }
    }

    private func stopCurrentPlayer() {
        currentPlayer?.pause()
        currentPlayer = nil
    }

    private func moveToNext() async {
        guard let slideshow else { return }

        var next: SlideshowAsset? = nil
        do {
            next = try await slideshow.next()
        } catch {
            showError("couldn't fetch the next asset: \(error)")
            return
        }

        if let next {
            stopCurrentPlayer()

            Task {
                await loadCurrentAsset(slideshowAsset: next)
            }
        } else {
            // later asset doesn't exist
            stopSlideshowTimer()
            stopProgressBarTimer()
            currentPlayer?.pause()
            assetProgress = 0

            if settings.slideshowDirection == .newestToOldest {
                showInformation(
                    "can't go back, this is the first image / video"
                )
            } else {
                showInformation("the end!")
            }
        }
    }

    private func moveToPrevious() async {
        guard let slideshow else { return }

        var previous: SlideshowAsset? = nil
        do {
            previous = try await slideshow.previous()
        } catch {
            showError("couldn't fetch the previous asset: \(error)")
            return
        }

        if let previous {
            stopCurrentPlayer()

            Task {
                await loadCurrentAsset(slideshowAsset: previous)
            }
        } else {
            // earlier asset doesn't exist
            stopSlideshowTimer()
            stopProgressBarTimer()
            currentPlayer?.pause()
            assetProgress = 0

            if settings.slideshowDirection == .newestToOldest {
                showInformation("the end!")
            } else {
                showInformation(
                    "can't go back, this is the first image / video"
                )
            }
        }
    }

    private func initSlideshow(albumID: AlbumID) async {
        do {
            slideshow = try await SlideshowSequencer(
                playlistGetter: SlideshowPlaylistGetter(
                    settings: settings,
                    immichClient: ImmichClient.shared,
                ),
                initialAlbumID: initialAlbumID,
                initialAssetID: initialAssetID,
            )
            guard let slideshow else { return }

            if let currentAsset = try await slideshow.current() {
                await loadCurrentAsset(slideshowAsset: currentAsset)
            }
        } catch {
            showError(error.localizedDescription)
            logError(error)
        }
    }
}
