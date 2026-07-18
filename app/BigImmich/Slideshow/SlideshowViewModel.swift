import AVKit
import ImmichAPI
import Observation
import SwiftUI

@MainActor
@Observable
final class SlideshowViewModel {
    let initialAlbumID: AlbumID
    let initialAlbumName: AlbumName
    let initialAssetID: AssetID?

    var slideshowAsset: SlideshowAsset?

    var userAssetIndex: Int = 0
    var userAssetsCount: Int = 0
    var userDateTime: String = ""
    var userLocation: String = ""

    var currentImage: Image?
    var currentPlayer: AVPlayer?
    var videoState: VideoState = .loading

    var isLoading = false
    var errors: [String] = []
    var informations: [String] = []

    var slideshowIsRunning = true
    var showAssetDetails = false
    var assetProgress: Double = 0.0

    @ObservationIgnored let settings = SlideshowSettings()

    @ObservationIgnored let immichClient: ImmichClientProtocol

    @ObservationIgnored private var slideshow: SlideshowSequencer?
    @ObservationIgnored private var previousAlbumID: AlbumID?

    /// Set by `stop()` when the view disappears. The async load/advance loop
    /// (`loadCurrentAsset` ⇄ `moveToNext`/`moveToPrevious`) checks this so a slideshow
    /// full of faulty assets doesn't keep churning — and spamming errors — after exit.
    @ObservationIgnored private var isStopped = false

    @ObservationIgnored private let videoController = VideoPlaybackController()

    @ObservationIgnored private var clearErrors: DispatchWorkItem?
    @ObservationIgnored private var slideshowTimer: Timer?
    @ObservationIgnored private var progressBarTimer: Timer?

    @ObservationIgnored private let imageLoader: AssetImageLoader

    init(
        initialAlbumID: AlbumID,
        initialAlbumName: AlbumName,
        initialAssetID: AssetID?,
        immichClient: ImmichClientProtocol = ImmichClient.shared
    ) {
        self.initialAlbumID = initialAlbumID
        self.initialAlbumName = initialAlbumName
        self.initialAssetID = initialAssetID
        self.immichClient = immichClient
        imageLoader = AssetImageLoader(
            immichClient: immichClient,
            cacheCountLimit: 10
        )
        videoController.onProgress = { [weak self] progress in
            self?.assetProgress = progress
        }
        videoController.onStateChange = { [weak self] state in
            guard let self else { return }
            videoState = state
            if case let .failed(message) = state {
                showError(message)
                Task { await self.moveToNext() }
            }
        }
    }

    func start() async {
        isStopped = false
        await initSlideshow()
    }

    func stop() {
        isStopped = true
        stopSlideshowTimer()
        stopProgressBarTimer()
        stopCurrentPlayer()
    }

    func clearImageCache() {
        imageLoader.clear()
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
            if currentPlayer != nil {
                videoController.seek(seconds: 15)
            }
        case .down:
            if currentPlayer != nil {
                videoController.seek(seconds: -15)
            }
        default:
            break
        }
    }

    func togglePause() {
        withAnimation {
            slideshowIsRunning.toggle()
        }
        applyPlaybackState()
        if !slideshowIsRunning {
            showAssetDetails = true
        }
    }

    /// Applies the current `slideshowIsRunning` state to whatever asset is showing, so a paused
    /// slideshow keeps videos paused and images from advancing — and resuming does the reverse.
    /// This is the single pause switch for both media types.
    private func applyPlaybackState() {
        if currentPlayer != nil {
            if slideshowIsRunning {
                videoController.play()
            } else {
                videoController.pause()
            }
        } else if currentImage != nil {
            if slideshowIsRunning {
                startImageTimers()
            } else {
                stopSlideshowTimer()
                stopProgressBarTimer()
            }
        }
    }

    private func loadAssetMetadata(for assetID: AssetID) {
        let client = immichClient
        Task { [weak self] in
            guard let detailed = try? await client.getAsset(assetID: assetID)
            else { return }

            guard let self, slideshowAsset?.asset.id == assetID else { return }
            userDateTime = formattedCaptureDate(detailed)
            userLocation = formattedLocation(detailed)
        }
    }

    private func loadCurrentAsset(slideshowAsset: SlideshowAsset) async {
        guard !isStopped else { return }

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
        // The album/search response already carries EXIF, so only fetch the full
        // asset when it's missing (e.g. a Top Shelf deep link) — saves one network
        // round-trip per photo, which matters on a slow connection.
        if asset.exifInfo == nil {
            loadAssetMetadata(for: asset.id)
        }

        if asset.assetType == .image {
            do {
                currentImage = try await imageLoader.load(
                    assetID: asset.id,
                    size: settings.slideshowImageQuality.thumbnailSize,
                    retries: 3
                )
            } catch {
                showError("loading image failed: id=\(asset.id)")
                logError(error)
                await moveToNext()
                return
            }

            if slideshowIsRunning {
                startImageTimers()
            }
        } else if asset.assetType == .video {
            let playbackURL: URL
            do {
                playbackURL = try await immichClient.videoPlaybackURL(
                    assetID: asset.id
                )
            } catch {
                showError(
                    "loading video failed: failed to construct playback URL"
                )
                return
            }

            videoController.start(
                url: playbackURL,
                autoplay: slideshowIsRunning,
                onEnded: { [weak self] in
                    Task { await self?.moveToNext() }
                }
            )
            currentPlayer = videoController.player
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
        guard asset.assetType == .image else { return }

        do {
            try await imageLoader.load(
                assetID: asset.id,
                size: settings.slideshowImageQuality.thumbnailSize,
                retries: 2
            )
        } catch {
            logError(error)
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

    private func stopCurrentPlayer() {
        videoController.stop()
        currentPlayer = nil
    }

    private func moveToNext() async {
        guard !isStopped, let slideshow else { return }

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
            videoController.pause()
            assetProgress = 0

            if settings.slideshowDirection == .newestToOldest {
                showInformation("can't go back, this is the first image / video")
            } else {
                showInformation("the end!")
            }
        }
    }

    private func moveToPrevious() async {
        guard !isStopped, let slideshow else { return }

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
            videoController.pause()
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
                    immichClient: immichClient
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
