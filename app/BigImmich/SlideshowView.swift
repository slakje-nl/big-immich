import AVKit
import ImmichAPI
import Sentry
import SwiftUI

struct SlideshowView: View {
    let initialAlbumID: AlbumID
    let initialAlbumName: AlbumName
    let initialAssetID: AssetID?
    let onExit: (AlbumID, AlbumName, AssetID?) -> Void

    @State private var allAlbums: [Album] = []
    @State private var album: Album? = nil
    @State private var assetIndex: Int = 0

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

    // loading settings
    @AppStorage("slideshowInterval") private var slideshowInterval: Int = 5
    @AppStorage("slideshowDirection") private var slideshowDirection:
        SlideshowDirection = .oldestToNewest
    @AppStorage("slideshowLeftAction") private var slideshowLeftAction:
        SlideshowAction = .goToNext
    @AppStorage("slideshowRightAction") private var slideshowRightAction:
        SlideshowAction = .goToPrevious
    @AppStorage("slideshowOnceEndedAction") private
        var slideshowOnceEndedAction: SlideshowOnceEndedAction = .stopAndNotify
    @AppStorage("slideshowShowProgressBar") private
        var slideshowShowProgressBar: SlideshowShowProgressBar = .always

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

    // showing first / last image notice
    @State private var isLastImage = false
    @State private var isFirstImage = false

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

            if isLastImage {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("the end!")
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(16)
                            .background(
                                Color.black.opacity(0.5).cornerRadius(12)
                            )
                        Spacer()
                    }
                }
                .transition(.opacity)
            }

            if isFirstImage {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("sorry, first image!")
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(16)
                            .background(
                                Color.black.opacity(0.5).cornerRadius(12)
                            )
                        Spacer()
                    }
                }
                .transition(.opacity)
            }

            // progress bar
            if slideshowShowProgressBar == .always {
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

            // errors overlay
            if !errors.isEmpty {
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

            if let album = album {
                onExit(album.id, album.albumName, album.assets[assetIndex].id)
            } else {
                onExit(initialAlbumID, initialAlbumName, initialAssetID)
            }
        }
        .onMoveCommand { direction in
            handleMoveCommand(direction)
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

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            stopSlideshowTimer()
            stopProgressBarTimer()

            switch slideshowLeftAction {
            case .goToNext:
                moveToLater()
            case .goToPrevious:
                moveToEarlier()
            }
        case .right:
            stopSlideshowTimer()
            stopProgressBarTimer()

            switch slideshowRightAction {
            case .goToNext:
                moveToLater()
            case .goToPrevious:
                moveToEarlier()
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

    private func loadCurrentAsset() async {
        // stop actions
        stopSlideshowTimer()
        stopProgressBarTimer()
        stopCurrentPlayer()

        guard let album else { return }
        guard album.assets.indices.contains(assetIndex) else { return }
        let asset = album.assets[assetIndex]

        // clear state
        currentImage = nil
        currentPlayer = nil
        assetProgress = 0.0

        // load variables for the overlay when paused
        if slideshowDirection == .oldestToNewest {
            userAssetIndex = album.assets.count - assetIndex
        } else {
            userAssetIndex = assetIndex + 1
        }
        userAssetsCount = album.assets.count
        userDateTime = formatDate(asset: asset)
        userLocation = formatLocation(asset: asset)

        do {
            if asset.type.uppercased() == "IMAGE" {
                if let cache = imageCache, let nextImage = cache.get(asset.id) {
                    currentImage = nextImage
                } else {
                    let data = try await ImmichAPI.shared.loadMediaWithRetries(
                        path: "/api/assets/\(asset.id.string)/thumbnail",
                        queryParams: ["size": "fullsize"],
                        retries: 3,
                    )
                    if let uiImage = UIImage(data: data) {
                        currentImage = Image(uiImage: uiImage)
                    } else {
                        showError("loading image failed: id=\(asset.id)")
                        self.moveToNext()
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

                let oldAssetIndex = assetIndex
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    [oldAssetIndex] in
                    // monitoring if video is started and playing in 5s
                    // there's no reason for 5s, it just sounds like a good amount of time
                    // FIXME: this is sometimes flaky, I'm not yet sure why
                    guard let player = self.currentPlayer else { return }
                    guard self.assetIndex == oldAssetIndex else { return }

                    if player.status == .failed
                        || player.currentItem?.status == .failed
                    {
                        self.showError("video failed to load")
                        self.moveToNext()
                        return
                    } else if player.timeControlStatus != .playing {
                        self.showError("video did not start playing")
                        self.moveToNext()
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
                        moveToNext()
                    }
                }
            }
        } catch {
            showError(error.localizedDescription)
            logError(error)
            isLoading = false
            moveToNext()
            return
        }

        await preloadAssets()
    }

    private func preloadAssets() async {
        if let laterAssetIndex = getLaterAssetIndex() {
            await preloadAsset(
                assetIndex: laterAssetIndex,
            )
        }
        if let earlierAssetIndex = getEarlierAssetIndex() {
            await preloadAsset(
                assetIndex: earlierAssetIndex,
            )
        }
    }

    private func preloadAsset(assetIndex: Int) async {
        guard let album else { return }

        let nextAsset = album.assets[assetIndex]

        if let cache = imageCache, nextAsset.type.uppercased() == "IMAGE" {
            guard cache.get(nextAsset.id) == nil else { return }

            do {
                let data = try await ImmichAPI.shared.loadMediaWithRetries(
                    path: "/api/assets/\(nextAsset.id.string)/thumbnail",
                    queryParams: ["size": "fullsize"],
                    retries: 2
                )
                if let uiImage = UIImage(data: data) {
                    cache.set(nextAsset.id, value: Image(uiImage: uiImage))
                }
            } catch {
                showError(
                    "preloading image failed: \(error.localizedDescription)"
                )
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
        let totalSteps = Double(slideshowInterval) / step
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
            withTimeInterval: TimeInterval(slideshowInterval),
            repeats: false
        ) { _ in
            moveToNext()
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

    private func moveToNext() {
        if slideshowDirection == .oldestToNewest {
            moveToLater()
        } else {
            moveToEarlier()
        }
    }

    private func moveToLater() {
        isLastImage = false
        isFirstImage = false

        if let nextIndex = getLaterAssetIndex() {
            stopCurrentPlayer()

            assetIndex = nextIndex
            Task {
                await loadCurrentAsset()
            }
        } else {
            // later asset doesn't exist
            stopSlideshowTimer()
            stopProgressBarTimer()
            currentPlayer?.pause()
            assetProgress = 0

            if slideshowDirection == .oldestToNewest {
                isLastImage = true
            } else {
                isFirstImage = true
            }
        }
    }

    private func moveToEarlier() {
        isLastImage = false
        isFirstImage = false

        if let previousIndex = getEarlierAssetIndex() {
            stopCurrentPlayer()

            assetIndex = previousIndex
            Task {
                await loadCurrentAsset()
            }
        } else {
            // earlier asset doesn't exist
            stopSlideshowTimer()
            stopProgressBarTimer()
            currentPlayer?.pause()
            assetProgress = 0

            if slideshowDirection == .oldestToNewest {
                isFirstImage = true
            } else {
                isLastImage = true
            }

        }
    }

    private func getLaterAssetIndex() -> Int? {
        guard let album else { return nil }

        if assetIndex > 0 {
            return assetIndex - 1
        }

        switch slideshowOnceEndedAction {
        case .stopAndNotify:
            return nil
        case .startAgain:
            return album.assets.count - 1
        case .loadAnotherAlbum:
            return nil  // "TODO"
        }

    }

    private func getEarlierAssetIndex() -> Int? {
        guard let album else { return nil }

        if assetIndex < album.assets.count - 1 {
            return assetIndex + 1
        }

        switch slideshowOnceEndedAction {
        case .stopAndNotify:
            return nil
        case .startAgain:
            return 0
        case .loadAnotherAlbum:
            return nil  // "TODO"
        }
    }

    private func initSlideshow(albumID: AlbumID) async {
        await loadAlbum(albumID: albumID)
        guard let album else { return }

        var defaultAssetIndex: Int
        if slideshowDirection == .oldestToNewest {
            defaultAssetIndex = album.assets.count - 1
        } else {
            defaultAssetIndex = 0
        }

        assetIndex =
            album.assets.firstIndex { $0.id == initialAssetID }
            ?? defaultAssetIndex

        await loadCurrentAsset()
    }

    private func loadAlbum(albumID: AlbumID) async {
        isLoading = true
        do {
            if allAlbums.count == 0 {
                allAlbums = try await ImmichClient.shared.findAlbums()
            }

            album = try await ImmichAPI.shared.loadObject(
                path: "/api/albums/\(albumID.string)",
                queryParams: [:],
            )
        } catch {
            showError(error.localizedDescription)
            logError(error)
        }
        isLoading = false
    }
}
