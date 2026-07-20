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
    /// The full asset (with complete EXIF: dimensions, size, file name) fetched for the nerd-stats
    /// overlay — the album/search response's EXIF is partial. `nil` until fetched.
    var detailedAsset: AlbumAsset?

    var userAssetIndex: Int = 0
    var userAssetsCount: Int = 0
    var userDateTime: String = ""
    var userLocation: String = ""

    var currentImage: Image?
    var currentPlayer: AVPlayer?
    var videoState: VideoState = .loading
    var videoStats = VideoStats()

    var isLoading = false
    var errors: [String] = []
    var informations: [String] = []

    var slideshowIsRunning = true
    var showAssetDetails = false
    var assetProgress: Double = 0.0

    /// On-screen options overlay (up button): `optionsMenuIndex` is the highlighted row into
    /// `optionsMenuItems` (interval for photos, the nerd-stats toggle for videos).
    var showOptionsMenu = false
    var optionsMenuIndex = 0
    /// Whether the "nerd stats" overlay is visible. Toggled from the options menu; seeded from
    /// (and persisted back to) settings so a preference survives across launches.
    var showVideoStats = false
    /// Observable mirror of the slideshow interval shown live in the options overlay. `settings`
    /// is `@ObservationIgnored`, so the overlay reads this to re-render when the value changes.
    var displayInterval = 5
    /// Observable mirrors of the video-engine / quality settings, for the same reason as
    /// `displayInterval`: the options overlay reads these to re-render live.
    var displayVideoEngine: SlideshowVideoEngine = .classic
    var displayVideoQuality: SlideshowVideoQuality = .fhd1080
    /// The engine actually in use after runtime resolution — equals `displayVideoEngine` unless
    /// HLS was requested but the server couldn't serve it, in which case it falls back to
    /// `.classic`. Shown in the nerd-stats overlay.
    var activeVideoEngine: SlideshowVideoEngine = .classic
    /// A short-lived "peek" of the video progress bar while playing (the down button). Ignored
    /// while paused, where the bar is shown permanently.
    var scrubberPeek = false
    @ObservationIgnored private var scrubberPeekTimer: Timer?

    /// When the user last pressed left/right while scrubbing a paused video. Used to require a
    /// short quiet gap before a press at the very start/end changes the asset — so overshooting
    /// to a boundary and holding there doesn't accidentally skip to the previous/next asset.
    @ObservationIgnored private var lastScrubInstant: ContinuousClock.Instant?
    private static let scrubBoundaryGrace: Duration = .seconds(1.2)

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

    /// The single next video warmed ahead of time (connection + initial data), so it starts
    /// sooner. Consumed when its asset becomes current; cleared on stop. Only ever one, to
    /// avoid holding several open streams.
    @ObservationIgnored private var prewarmedVideo: (id: AssetID, asset: AVURLAsset)?

    /// The active HLS session (asset it belongs to + server session id), so it can be released
    /// on the server when we move off the video or exit. `nil` for the classic engine.
    @ObservationIgnored private var currentHLS: (assetID: AssetID, sessionID: String)?

    /// The resolved HLS stream for the current video, kept so the quality menu can switch
    /// renditions without a new server round-trip (it reuses the same session's variant URLs).
    @ObservationIgnored private var currentHLSStream: HLSStream?

    /// Set once we've told the user that HLS was requested but fell back to Classic (e.g. the
    /// server has real-time transcoding disabled), so the notice shows once, not per video.
    @ObservationIgnored private var hlsFallbackNotified = false

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
        showVideoStats = settings.slideshowShowVideoStats
        videoController.onProgress = { [weak self] progress in
            self?.assetProgress = progress
        }
        videoController.onStateChange = { [weak self] state in
            guard let self else { return }
            videoState = state
            // `.buffering`/`.loading` are patient states — we wait for the buffer, never skip.
            // Only a real failure acts: an HLS failure retries on Classic, otherwise we advance.
            if case let .failed(message) = state {
                Task { await self.handleVideoFailure(message) }
            }
        }
        videoController.onStatsChange = { [weak self] stats in
            self?.videoStats = stats
        }
    }

    func start() async {
        isStopped = false
        syncOverlayMirrors()
        await initSlideshow()
    }

    /// Refreshes the observable mirrors from the persisted settings (see their declaration).
    private func syncOverlayMirrors() {
        showVideoStats = settings.slideshowShowVideoStats
        displayInterval = settings.slideshowInterval
        displayVideoEngine = settings.slideshowVideoEngine
        displayVideoQuality = settings.slideshowVideoQuality
        activeVideoEngine = settings.slideshowVideoEngine
    }

    func stop() {
        isStopped = true
        stopSlideshowTimer()
        stopProgressBarTimer()
        stopCurrentPlayer()
        cancelScrubberPeek()
        prewarmedVideo = nil
        // The in-memory image cache only serves this session; drop it on exit rather than
        // key it by rendition size. Cheap to rebuild — the on-disk cache backs the next run.
        imageLoader.clear()
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
        // The options overlay captures the remote while it's open: up/down navigate rows,
        // left/right adjust the highlighted row's value.
        if showOptionsMenu {
            switch direction {
            case .up, .down: moveOptionsMenu(direction)
            case .left, .right: adjustCurrentOption(direction)
            default: break
            }
            return
        }

        // Up always opens the options overlay (over a photo or video), pausing playback.
        if direction == .up, currentImage != nil || currentPlayer != nil {
            openOptionsMenu()
            return
        }
        // Down peeks the video progress bar: a couple of seconds while playing, or permanently
        // while paused. It never hides the bar.
        if direction == .down, currentPlayer != nil {
            peekScrubber()
            return
        }

        // Whenever the video progress bar is on screen (paused, or a down-button peek), left/right
        // scrub — so a peek makes scrubbing available even while playing. The bar being hidden is
        // what keeps left/right on changing assets. At the very start/end a press falls through to
        // prev/next asset, but only after a short quiet gap so overshooting to a boundary stays put.
        if showVideoScrubber, direction == .left || direction == .right {
            let forward = direction == .right
            let pastBoundary = (forward && videoAtEnd) || (!forward && videoAtStart)
            let now = ContinuousClock.now
            if !pastBoundary {
                scrubVideo(forward: forward)
                lastScrubInstant = now
                // Scrubbing during a peek keeps the bar up (no-op while paused).
                peekScrubber()
                return
            }
            // At the boundary: absorb the press if the user is still actively pressing (keeps
            // the timer alive); only a press after the grace period changes the asset.
            if let last = lastScrubInstant, now - last < Self.scrubBoundaryGrace {
                lastScrubInstant = now
                return
            }
            lastScrubInstant = nil
        }

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
        default:
            // Up/down are unused during playback — pause and scrub with left/right instead.
            break
        }
    }

    func togglePause() {
        withAnimation {
            slideshowIsRunning.toggle()
        }
        applyPlaybackState()
        // Pausing shows the bar permanently; resuming hides it — either way the peek is moot.
        cancelScrubberPeek()
        if !slideshowIsRunning {
            showAssetDetails = true
        }
    }

    /// The video progress bar is shown whenever a video is paused (permanently, regardless of how
    /// it was paused or for how long), or briefly while playing after the down button (a peek).
    /// Hidden while the options overlay is up. (Left/right only scrubs while paused — see above.)
    var showVideoScrubber: Bool {
        guard currentPlayer != nil, !showOptionsMenu else { return false }
        return !slideshowIsRunning || scrubberPeek
    }

    /// The down button: peek the progress bar. While paused it's already shown permanently, so
    /// this only matters while playing — show it, then auto-hide after a couple of seconds
    /// (pressing again restarts the timer). Never hides the bar itself.
    func peekScrubber() {
        guard currentPlayer != nil, slideshowIsRunning else { return }
        scrubberPeek = true
        scrubberPeekTimer?.invalidate()
        scrubberPeekTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                withAnimation { self.scrubberPeek = false }
                self.scrubberPeekTimer = nil
            }
        }
    }

    private func cancelScrubberPeek() {
        scrubberPeekTimer?.invalidate()
        scrubberPeekTimer = nil
        scrubberPeek = false
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

    /// Seconds of the current video, for the scrubber label. 0 for photos / unknown.
    var videoDurationSeconds: Double {
        videoController.durationSeconds
    }

    /// Current playhead position of the video in seconds.
    var videoCurrentSeconds: Double {
        videoController.currentSeconds
    }

    /// Whether the video is at its very start / end. Uses the optimistic `assetProgress` bar so
    /// the boundary — and therefore the scrubber hints — update the instant you scrub, in lockstep
    /// with the bar and the time label.
    var videoAtStart: Bool {
        assetProgress <= 0.001
    }

    var videoAtEnd: Bool {
        assetProgress >= 0.999
    }

    /// The current playhead in seconds to *show* on the scrubber: derived from the bar position so
    /// it tracks scrubbing immediately (the player's own time lags a paused seek).
    var videoDisplaySeconds: Double {
        videoController.durationSeconds * assetProgress
    }

    /// The per-press scrub step (seconds) for the current video, shown in the scrubber hints.
    var videoScrubStepSeconds: Int {
        Int(Self.scrubStep(forDuration: videoController.durationSeconds))
    }

    /// Seeks one scrub step (scaled to the video's length) and reflects it in the progress bar
    /// immediately, so scrubbing feels responsive even while paused (when the time observer is
    /// idle). Short clips step finely; long ones step coarsely so you can traverse them quickly.
    private func scrubVideo(forward: Bool) {
        let duration = videoController.durationSeconds
        let delta = (forward ? 1.0 : -1.0) * Self.scrubStep(forDuration: duration)
        videoController.seek(seconds: delta)
        guard duration > 0 else { return }
        assetProgress = min(max(assetProgress + delta / duration, 0), 1)
    }

    /// The per-press scrub step for a video of the given length.
    private static func scrubStep(forDuration duration: Double) -> Double {
        switch duration {
        case ..<20: 2 // ≤20s clips: 2s taps
        case ..<60: 5 // ≤1min: 5s
        case ..<300: 15 // ≤5min: 15s
        case ..<1200: 30 // ≤20min: 30s
        default: 60 // longer: 1min
        }
    }

    private func loadAssetMetadata(for assetID: AssetID) {
        let client = immichClient
        Task { [weak self] in
            guard let detailed = try? await client.getAsset(assetID: assetID)
            else { return }

            guard let self, slideshowAsset?.asset.id == assetID else { return }
            detailedAsset = detailed
            userDateTime = formattedCaptureDate(detailed)
            userLocation = formattedLocation(detailed)
        }
    }

    /// Ensures the full asset (with complete EXIF) is loaded, e.g. when the stats overlay is
    /// switched on for the current photo.
    func loadDetailedAssetIfNeeded() {
        guard detailedAsset == nil, let assetID = slideshowAsset?.asset.id else { return }
        loadAssetMetadata(for: assetID)
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
        detailedAsset = nil
        // Per-asset UI state resets so nothing leaks across a transition.
        showOptionsMenu = false
        cancelScrubberPeek()
        lastScrubInstant = nil

        userAssetIndex = slideshowAsset.counter.current
        userAssetsCount = slideshowAsset.counter.total
        userDateTime = formattedCaptureDate(asset)
        userLocation = formattedLocation(asset)
        // The album/search response carries partial EXIF, so fetch the full asset when it's
        // missing (e.g. a Top Shelf deep link) or when the nerd-stats overlay needs the complete
        // metadata (dimensions/size). Otherwise skip it — a round-trip that matters on a slow link.
        if asset.exifInfo == nil || showVideoStats {
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
            let source: VideoSource
            if let prewarmed = prewarmedVideo, prewarmed.id == asset.id {
                // A prewarmed video is always the classic progressive stream (HLS isn't prewarmed).
                prewarmedVideo = nil
                source = VideoSource(asset: prewarmed.asset, engine: .classic, variantLabel: "Classic")
            } else if let resolved = await makeVideoSource(for: asset) {
                source = resolved
            } else {
                showError("loading video failed: failed to construct playback URL")
                return
            }

            applyVideoSource(source, assetID: asset.id, startAt: 0)
            // A video that loads while the slideshow is paused (e.g. navigated to from a paused
            // asset) shows its progress bar automatically via `showVideoScrubber`.
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

        let upcoming = await (try? slideshow.previewNext(count: 2)) ?? []
        let earlier = await (try? slideshow.previewPrevious(count: 2)) ?? []

        await withTaskGroup(of: Void.self) { group in
            for slide in upcoming + earlier where slide.asset.assetType == .image {
                group.addTask { [weak self] in
                    await self?.preloadImage(asset: slide.asset)
                }
            }
        }

        // Warm only the immediate next video, to avoid opening several streams at once.
        // Skippable from Settings if prewarming ever causes trouble on a given setup.
        // HLS is not prewarmed: warming its master would spin up a second server-side
        // transcoding session for a video we may never reach.
        if settings.slideshowPreloadVideos,
           settings.slideshowVideoEngine == .classic,
           let next = upcoming.first, next.asset.assetType == .video
        {
            await prewarmVideo(asset: next.asset)
        }
    }

    private func preloadImage(asset: AlbumAsset) async {
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

    /// A row in the in-slideshow options overlay (opened with the up button). Photos show the
    /// interval; videos show the nerd-stats toggle. Adjusted with left/right (or select).
    enum OptionRow: Identifiable, Equatable {
        case interval
        case toggleStats
        case quality

        var id: String {
            switch self {
            case .interval: "interval"
            case .toggleStats: "stats"
            case .quality: "quality"
            }
        }
    }

    var optionsMenuItems: [OptionRow] {
        if currentPlayer != nil {
            // Video: toggle nerd stats, plus a forced-quality row — but only on the adaptive (HLS)
            // engine, which is what quality applies to. The engine itself is chosen in Settings.
            var items: [OptionRow] = [.toggleStats]
            if displayVideoEngine == .hls {
                items.insert(.quality, at: 0)
            }
            return items
        }
        if currentImage != nil {
            return [.interval, .toggleStats]
        }
        return []
    }

    /// Opens the options overlay over the current asset, always pausing playback — while it's
    /// open you can only change settings; closing it resumes the slideshow.
    func openOptionsMenu() {
        guard currentImage != nil || currentPlayer != nil else { return }
        slideshowIsRunning = false
        applyPlaybackState()
        cancelScrubberPeek()
        optionsMenuIndex = 0
        withAnimation { showOptionsMenu = true }
    }

    /// Closes the overlay and resumes the slideshow — the same as pressing play. For a photo this
    /// restarts its interval from zero; a video resumes from where it was.
    func closeOptionsMenu() {
        withAnimation { showOptionsMenu = false }
        slideshowIsRunning = true
        applyPlaybackState()
    }

    /// Moves the menu highlight up/down (clamped at the ends).
    func moveOptionsMenu(_ direction: MoveCommandDirection) {
        let count = optionsMenuItems.count
        guard count > 0 else { return }
        switch direction {
        case .up: optionsMenuIndex = max(0, optionsMenuIndex - 1)
        case .down: optionsMenuIndex = min(count - 1, optionsMenuIndex + 1)
        default: break
        }
    }

    private func currentOptionRow() -> OptionRow? {
        let items = optionsMenuItems
        guard items.indices.contains(optionsMenuIndex) else { return nil }
        return items[optionsMenuIndex]
    }

    /// Left/right on the highlighted row: the interval steps (clamped at the ends), and the
    /// nerd-stats row flips too. Off-centre touchpad clicks land as a directional press rather than
    /// a select, so honouring left/right here is what makes the toggle reliable to flip.
    private func adjustCurrentOption(_ direction: MoveCommandDirection) {
        let forward = direction == .right
        switch currentOptionRow() {
        case .interval:
            let value = displayInterval + (forward ? 1 : -1)
            let clamped = min(max(value, 1), 60)
            settings.slideshowInterval = clamped
            displayInterval = clamped
        case .toggleStats:
            toggleVideoStats()
        case .quality:
            cycleQuality(forward: forward, wrap: false)
        case .none:
            break
        }
    }

    /// The select (middle) button acts on the highlighted row: flips the nerd-stats toggle, or
    /// steps quality one rung (wrapping past the end). Interval is left/right only.
    func handleSelect() {
        guard showOptionsMenu else { return }
        switch currentOptionRow() {
        case .toggleStats:
            toggleVideoStats()
        case .quality:
            cycleQuality(forward: true, wrap: true)
        case .interval, .none:
            break
        }
    }

    private func toggleVideoStats() {
        showVideoStats.toggle()
        settings.slideshowShowVideoStats = showVideoStats
        if showVideoStats {
            loadDetailedAssetIfNeeded()
        }
    }

    // MARK: - Video engine (Classic / adaptive HLS)

    /// A ready-to-play video: the AVFoundation asset plus how it was resolved (engine, quality
    /// label, HLS session for cleanup, and any bitrate cap).
    private struct VideoSource {
        let asset: AVURLAsset
        let engine: SlideshowVideoEngine
        let variantLabel: String
        var sessionID: String?
        var maxBitrate: Double = 0
    }

    /// AVFoundation applies these header fields to every request for the asset — including the
    /// HLS variant playlists and segments, which is why HLS must authenticate by header (Immich
    /// advertises those sub-resources as relative URIs, so query-param auth is dropped on them).
    private static let httpHeaderFieldsOption = "AVURLAssetHTTPHeaderFieldsKey"

    /// Resolves how to play `asset`: HLS when the engine is set to it and the server supports it,
    /// otherwise the classic progressive stream. A failed HLS resolution (e.g. the server has
    /// real-time transcoding disabled) transparently falls back to classic.
    private func makeVideoSource(for asset: AlbumAsset) async -> VideoSource? {
        if settings.slideshowVideoEngine == .hls,
           let hls = await makeHLSSource(for: asset)
        {
            return hls
        }
        guard let url = try? await immichClient.videoPlaybackURL(assetID: asset.id) else {
            return nil
        }
        return VideoSource(asset: AVURLAsset(url: url), engine: .classic, variantLabel: "Classic")
    }

    private func makeHLSSource(for asset: AlbumAsset) async -> VideoSource? {
        let stream: HLSStream
        do {
            stream = try await immichClient.hlsStream(assetID: asset.id)
        } catch {
            // Surface the reason in the on-device debug logs so a fallback can be analysed.
            AppLog.shared.log(
                "HLS unavailable for asset \(asset.id.string), falling back to Classic: "
                    + "\(error)\(Self.hlsFallbackHint(for: error))",
                level: .error,
                source: "Video"
            )
            return nil
        }
        currentHLSStream = stream
        let options = [Self.httpHeaderFieldsOption: stream.authHeaders]

        // Pinned quality → play one variant playlist directly, so ABR never drops below it.
        // Auto → hand over the master playlist and let AVFoundation adapt.
        if let height = settings.slideshowVideoQuality.maxHeight,
           let variant = stream.variant(forMaxHeight: height)
        {
            return VideoSource(
                asset: AVURLAsset(url: variant.playlistURL, options: options),
                engine: .hls,
                variantLabel: "\(variant.heightPixels)p",
                sessionID: stream.sessionID
            )
        }
        return VideoSource(
            asset: AVURLAsset(url: stream.masterURL, options: options),
            engine: .hls,
            variantLabel: "Auto",
            sessionID: stream.sessionID
        )
    }

    /// An actionable hint for common HLS failures, appended to the debug log.
    private static func hlsFallbackHint(for error: Error) -> String {
        switch error {
        case ImmichAPIError.httpErrorCode(statusCode: 404):
            " — the server has no stream metadata for this video yet. Run Immich's"
                + " Administration → Jobs → Extract Metadata (All) to backfill keyframes/packets."
        case ImmichAPIError.httpErrorCode(statusCode: 400):
            " — real-time transcoding is disabled on the server (Admin → Settings → Video)."
        default:
            ""
        }
    }

    /// Publishes a resolved `VideoSource`: records the engine/session, notes any HLS→Classic
    /// fallback, and starts playback (optionally resuming at `startAt`).
    private func applyVideoSource(_ source: VideoSource, assetID: AssetID, startAt: Double) {
        activeVideoEngine = source.engine
        currentHLS = source.sessionID.map { (assetID, $0) }
        notifyHLSFallbackIfNeeded(source: source)
        videoController.start(
            asset: source.asset,
            autoplay: slideshowIsRunning,
            forwardBufferDuration: 30,
            maxBitrate: source.maxBitrate,
            startAtSeconds: startAt,
            variantLabel: source.variantLabel,
            onEnded: { [weak self] in
                Task { await self?.moveToNext() }
            }
        )
        currentPlayer = videoController.player
    }

    /// Once per slideshow session, tells the user when HLS was requested but fell back to
    /// Classic; the underlying reason is already in the debug logs (see `makeHLSSource`).
    private func notifyHLSFallbackIfNeeded(source: VideoSource) {
        guard settings.slideshowVideoEngine == .hls, source.engine == .classic else { return }
        guard !hlsFallbackNotified else { return }
        hlsFallbackNotified = true
        showInformation("Adaptive (HLS) unavailable — using Classic. See Settings → Debug logs.")
    }

    /// Handles a fatal playback error. When an HLS stream fails mid-playback — e.g. the server
    /// 404s a variant it advertised, which its alpha real-time transcoder still does — we retry
    /// the *same* asset once on the classic engine (surfacing the usual blue notice via
    /// `applyVideoSource`) rather than skipping it. A classic failure, or a second failure after
    /// falling back, advances to the next asset.
    private func handleVideoFailure(_ message: String) async {
        guard activeVideoEngine == .hls,
              let asset = slideshowAsset?.asset, asset.assetType == .video
        else {
            showError(message)
            await moveToNext()
            return
        }

        AppLog.shared.log(
            "HLS playback failed for asset \(asset.id.string) (\(message)); retrying on Classic.",
            level: .error,
            source: "Video"
        )
        let resumeAt = videoController.currentSeconds
        endCurrentHLSSession()
        guard let url = try? await immichClient.videoPlaybackURL(assetID: asset.id) else {
            showError(message)
            await moveToNext()
            return
        }
        applyVideoSource(
            VideoSource(asset: AVURLAsset(url: url), engine: .classic, variantLabel: "Classic"),
            assetID: asset.id,
            startAt: resumeAt
        )
    }

    /// Releases the current HLS transcoding session on the server (best-effort), so it stops
    /// transcoding as soon as we leave the video.
    private func endCurrentHLSSession() {
        currentHLSStream = nil
        guard let current = currentHLS else { return }
        currentHLS = nil
        let client = immichClient
        Task { await client.endHLSSession(assetID: current.assetID, sessionID: current.sessionID) }
    }

    /// The quality values the Quality row cycles through — the full fixed set (Auto, then tallest
    /// to shortest), matching the Settings picker. A pinned height the server doesn't advertise
    /// resolves to the nearest available rung at play time (see `HLSStream.variant(forMaxHeight:)`).
    var qualityChoices: [SlideshowVideoQuality] {
        SlideshowVideoQuality.allCases
    }

    /// Steps the pinned quality through `qualityChoices` and applies it in place when a live HLS
    /// stream is playing (otherwise it just persists for the next HLS video).
    private func cycleQuality(forward: Bool, wrap: Bool) {
        let choices = qualityChoices
        guard !choices.isEmpty else { return }
        let current = choices.firstIndex(of: displayVideoQuality) ?? 0
        let next: Int = if wrap {
            forward
                ? (current + 1) % choices.count
                : (current - 1 + choices.count) % choices.count
        } else {
            forward ? min(current + 1, choices.count - 1) : max(current - 1, 0)
        }
        let chosen = choices[next]
        guard chosen != displayVideoQuality else { return }
        settings.slideshowVideoQuality = chosen
        displayVideoQuality = chosen
        if currentHLSStream != nil {
            reloadCurrentVideoQuality(chosen)
        }
    }

    /// Switches the playing video to `quality` in place, reusing the current HLS session's variant
    /// URLs and resuming from the current position — no extra server round-trip.
    private func reloadCurrentVideoQuality(_ quality: SlideshowVideoQuality) {
        guard let stream = currentHLSStream,
              let asset = slideshowAsset?.asset, asset.assetType == .video
        else { return }

        let resumeAt = videoController.currentSeconds
        let options = [Self.httpHeaderFieldsOption: stream.authHeaders]

        let url: URL
        let label: String
        if let height = quality.maxHeight, let variant = stream.variant(forMaxHeight: height) {
            url = variant.playlistURL
            label = "\(variant.heightPixels)p"
        } else {
            url = stream.masterURL
            label = "Auto"
        }

        videoController.start(
            asset: AVURLAsset(url: url, options: options),
            autoplay: slideshowIsRunning,
            forwardBufferDuration: 30,
            startAtSeconds: resumeAt,
            variantLabel: label,
            onEnded: { [weak self] in
                Task { await self?.moveToNext() }
            }
        )
        currentPlayer = videoController.player
        activeVideoEngine = .hls
    }

    /// Warms the next video's connection and initial data so playback starts sooner when we
    /// reach it. Only one video is ever warm at a time, so any earlier one is dropped.
    private func prewarmVideo(asset: AlbumAsset) async {
        guard prewarmedVideo?.id != asset.id else { return }
        prewarmedVideo = nil
        guard let url = try? await immichClient.videoPlaybackURL(assetID: asset.id)
        else { return }

        let urlAsset = AVURLAsset(url: url)
        prewarmedVideo = (asset.id, urlAsset)
        _ = try? await urlAsset.load(.isPlayable)
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
        ) { [weak self] _ in
            // Scheduled on the main run loop, so the callback runs on the main actor.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.assetProgress += 1 / totalSteps
                if self.assetProgress >= 1 {
                    self.stopProgressBarTimer()
                }
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
        endCurrentHLSSession()
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
