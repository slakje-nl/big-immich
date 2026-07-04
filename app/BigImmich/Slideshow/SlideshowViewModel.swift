import AVKit
import Combine
import ImmichAPI
import SwiftUI

final class SlideshowViewModel: ObservableObject {
    let initialAlbumID: AlbumID
    let initialAlbumName: AlbumName
    let initialAssetID: AssetID?

    @Published var slideshowAsset: SlideshowAsset?

    @Published var userAssetIndex: Int = 0
    @Published var userAssetsCount: Int = 0
    @Published var userDateTime: String = ""
    @Published var userLocation: String = ""

    @Published var currentImage: Image?
    @Published var currentPlayer: AVPlayer?

    @Published var isLoading = false
    @Published var errors: [String] = []
    @Published var informations: [String] = []

    @Published var slideshowIsRunning = true
    @Published var showAssetDetails = false
    @Published var assetProgress: Double = 0.0

    let settings = SlideshowSettings()

    private var slideshow: SlideshowSequencer?
    private var previousAlbumID: AlbumID?

    private var playerObserver: NSObjectProtocol?
    private var timeObserverToken: Any?
    private var videoPausedByUser = false

    private var clearErrors: DispatchWorkItem?
    private var slideshowTimer: Timer?
    private var progressBarTimer: Timer?

    private var imageCache: MemoryCache<AssetID, Image>?

    init(
        initialAlbumID: AlbumID,
        initialAlbumName: AlbumName,
        initialAssetID: AssetID?
    ) {
        self.initialAlbumID = initialAlbumID
        self.initialAlbumName = initialAlbumName
        self.initialAssetID = initialAssetID
    }

    func start() async {
        imageCache = MemoryCache(countLimit: 10, megaBytesLimit: nil)
        await initSlideshow()
    }

    func stop() {
        stopSlideshowTimer()
        stopProgressBarTimer()
        stopCurrentPlayer()
    }

    func clearImageCache() {
        imageCache?.clear()
    }

    func showError(_ message: String) {
        AppLog.shared.log(message, level: .error, source: "SlideshowView")
        withAnimation {
            errors.append(message)
        }

        clearErrors?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            withAnimation {
                self?.errors.removeAll()
            }
        }
        clearErrors = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: workItem)
    }

    func showInformation(_ message: String) {
        let easterEggs = [
            message,
            "=^..^=",
            "‘-‘_@_",
            "----{,_,\">",
            "><((((\">",
            "~~(^._.^)~~",
            ",/\\,/\\,/\\,/\\,/\\,/\\,o",
            "<(‘–‘)>",
            "///\\\\oo/\\\\\\"
        ]
        for (i, egg) in easterEggs.enumerated() {
            let count = informations.count { $0 == egg }

            if count >= 5 {
                withAnimation {
                    informations.removeAll { $0 == egg }
                    if easterEggs.indices.contains(i + 1) {
                        informations.append(easterEggs[i + 1])
                    }
                }
            }
        }

        withAnimation {
            informations.append(message)
        }
    }

    func handleMoveCommand(_ direction: MoveCommandDirection) async {
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

    func togglePause() {
        if let player = currentPlayer {
            let isPlaying =
                player.timeControlStatus == .playing && player.rate != 0

            if isPlaying {
                player.pause()
                videoPausedByUser = true
            } else {
                player.play()
                videoPausedByUser = false
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

    private func loadAssetMetadata(for assetID: AssetID) {
        Task { [weak self] in
            guard
                let detailed: AlbumAsset = try? await ImmichAPI.shared.loadObject(
                    path: "/api/assets/\(assetID.string)",
                    queryParams: [:]
                )
            else { return }

            guard let self, slideshowAsset?.asset.id == assetID else { return }
            userDateTime = formattedCaptureDate(detailed)
            userLocation = formattedLocation(detailed)
        }
    }

    private func loadCurrentAsset(slideshowAsset: SlideshowAsset) async {
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

        currentImage = nil
        currentPlayer = nil
        assetProgress = 0.0

        userAssetIndex = slideshowAsset.counter.current
        userAssetsCount = slideshowAsset.counter.total
        userDateTime = formattedCaptureDate(asset)
        userLocation = formattedLocation(asset)
        loadAssetMetadata(for: asset.id)

        do {
            if asset.assetType == .image {
                if let cache = imageCache, let nextImage = cache.get(asset.id) {
                    currentImage = nextImage
                } else {
                    let data = try await ImmichAPI.shared.loadMediaWithRetries(
                        path:
                        "/api/assets/\(slideshowAsset.asset.id.string)/thumbnail",
                        queryParams: ["size": "fullsize"],
                        retries: 3
                    )
                    if let uiImage = UIImage(data: data) {
                        currentImage = Image(uiImage: uiImage)
                    } else {
                        showError("loading image failed: id=\(asset.id)")
                        await moveToNext()
                        return
                    }
                }

                if slideshowIsRunning {
                    startImageTimers()
                }
            } else if asset.assetType == .video {
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
                videoPausedByUser = false

                let oldAssetID = asset.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    [weak self, oldAssetID] in
                    guard let self, let player = currentPlayer else { return }
                    guard let sAsset = self.slideshowAsset,
                          sAsset.asset.id == oldAssetID
                    else { return }

                    if player.status == .failed
                        || player.currentItem?.status == .failed
                    {
                        showError("video failed to load")
                        Task {
                            await self.moveToNext()
                        }
                        return
                    } else if player.timeControlStatus != .playing, !videoPausedByUser {
                        showError("video did not start playing")
                        Task {
                            await self.moveToNext()
                        }
                        return
                    }
                }

                observeVideoProgress()

                if let currentPlayer {
                    playerObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: currentPlayer.currentItem,
                        queue: .main
                    ) { [weak self] _ in
                        Task {
                            await self?.moveToNext()
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
            await preloadAsset(asset: laterAsset.asset)
        }
        if let earlierAsset = try? await slideshow.previewPrevious() {
            await preloadAsset(asset: earlierAsset.asset)
        }
    }

    private func preloadAsset(asset: AlbumAsset) async {
        if let cache = imageCache, asset.assetType == .image {
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
        ) { [weak self] t in
            self?.assetProgress += 1 / totalSteps
            if let progress = self?.assetProgress, progress >= 1 {
                t.invalidate()
            }
        }

        slideshowTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(settings.slideshowInterval),
            repeats: false
        ) { [weak self] _ in
            Task {
                await self?.moveToNext()
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
        removeTimeObserver()
        guard let player = currentPlayer else { return }

        let interval = CMTime(
            seconds: 0.05,
            preferredTimescale: CMTimeScale(NSEC_PER_SEC)
        )
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] time in
            if let duration = player.currentItem?.duration.seconds, duration > 0 {
                self?.assetProgress = min(time.seconds / duration, 1.0)
            }
        }
    }

    private func removeTimeObserver() {
        if let timeObserverToken {
            currentPlayer?.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
    }

    private func stopCurrentPlayer() {
        removeTimeObserver()
        if let playerObserver {
            NotificationCenter.default.removeObserver(playerObserver)
            self.playerObserver = nil
        }
        currentPlayer?.pause()
        currentPlayer = nil
    }

    private func moveToNext() async {
        guard let slideshow else { return }

        var next: SlideshowAsset?
        do {
            next = try await slideshow.next()
        } catch {
            showError("couldn't fetch the next asset: \(error)")
            return
        }

        if let next {
            stopCurrentPlayer()
            await loadCurrentAsset(slideshowAsset: next)
        } else {
            stopSlideshowTimer()
            stopProgressBarTimer()
            currentPlayer?.pause()
            assetProgress = 0

            if settings.slideshowDirection == .newestToOldest {
                showInformation("can't go back, this is the first image / video")
            } else {
                showInformation("the end!")
            }
        }
    }

    private func moveToPrevious() async {
        guard let slideshow else { return }

        var previous: SlideshowAsset?
        do {
            previous = try await slideshow.previous()
        } catch {
            showError("couldn't fetch the previous asset: \(error)")
            return
        }

        if let previous {
            stopCurrentPlayer()
            await loadCurrentAsset(slideshowAsset: previous)
        } else {
            stopSlideshowTimer()
            stopProgressBarTimer()
            currentPlayer?.pause()
            assetProgress = 0

            if settings.slideshowDirection == .newestToOldest {
                showInformation("the end!")
            } else {
                showInformation("can't go back, this is the first image / video")
            }
        }
    }

    private func initSlideshow() async {
        do {
            slideshow = try await SlideshowSequencer(
                playlistGetter: SlideshowPlaylistGetter(
                    settings: settings,
                    immichClient: ImmichClient.shared
                ),
                initialAlbumID: initialAlbumID,
                initialAssetID: initialAssetID
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
