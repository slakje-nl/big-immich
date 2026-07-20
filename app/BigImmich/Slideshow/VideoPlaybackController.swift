import AVKit
import ImmichAPI

/// Observed playback state of the current video, derived from `AVPlayer`/`AVPlayerItem`.
enum VideoState: Equatable {
    /// Loading the very first data — nothing has played yet.
    case loading
    /// Playback started but is now waiting for the buffer to refill (a mid-stream stall).
    /// Distinct from `loading` so the UI can say "buffering…" rather than restarting.
    case buffering
    case playing
    case paused
    /// The item failed to load, or the buffer stopped advancing for so long we treat it as dead.
    case failed(String)
}

/// Live playback statistics for the optional "nerd stats" overlay. All values are best-effort
/// reads from `AVPlayerItem`'s access log and current item; zero/`nil` when not yet known.
struct VideoStats: Equatable {
    /// Bitrate the server declares for the current variant (bits/s); 0 when unknown.
    var indicatedBitrate: Double = 0
    /// Throughput actually observed while downloading (bits/s); 0 when unknown.
    var observedBitrate: Double = 0
    /// Decoded frame size of the current rendition.
    var resolution: CGSize = .zero
    /// Number of playback stalls since the item started.
    var stalls: Int = 0
    /// Seconds of media buffered ahead of the playhead.
    var bufferedAhead: Double = 0
    /// Human label for the active quality (e.g. "1080p" or "Auto"), set by the caller.
    var variant: String?
    /// Video codec of the source track (e.g. "H.264", "HEVC"); empty until loaded.
    var codec: String = ""
    /// Nominal frame rate of the source track; 0 until loaded.
    var frameRate: Float = 0
    /// Colour primaries of the source track (e.g. "BT.709", "BT.2020"); empty until loaded.
    var colorSpace: String = ""
}

/// Owns the `AVPlayer` for the currently playing video: its lifecycle, the play-to-end and
/// periodic-time observers, seeking, buffering detection, playback state and live stats.
///
/// Playback state is read from the player itself — `AVPlayerItem.status` (real load failures,
/// with the underlying error) and `AVPlayer.timeControlStatus` (playing / waiting / paused) —
/// and `waitingToPlayAtSpecifiedRate` is reported as `buffering` once playback has begun so a
/// slow link shows a spinner instead of skipping the video. A watchdog only fails a stream
/// whose buffer stops growing for a long window, so "willing to wait" links keep buffering.
/// Every observer added here is torn down in `stop()`. Everything runs on the main actor; KVO
/// callbacks hop to it since AVFoundation may deliver them off the main thread.
@MainActor
final class VideoPlaybackController {
    /// How long the buffer may make no forward progress (while we're trying to play) before we
    /// give up. Generous on purpose: the design goal is to wait for quality, not to bail early.
    private static let stuckTimeout: Duration = .seconds(45)

    private(set) var player: AVPlayer?
    private(set) var state: VideoState = .loading

    private var endObserver: NSObjectProtocol?
    private var stalledObserver: NSObjectProtocol?
    private var timeObserverToken: Any?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var likelyToKeepUpObservation: NSKeyValueObservation?
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var watchdog: Task<Void, Never>?

    /// Whether playback has produced frames at least once, so we can tell a first-load
    /// (`loading`) apart from a mid-stream rebuffer (`buffering`).
    private var hasStartedPlaying = false
    /// A start position to seek to once the item is ready (used when switching quality so the
    /// new rendition resumes where the old one was). 0 means start from the beginning.
    private var pendingStartSeconds: Double = 0
    /// Label for the active quality, surfaced in the stats overlay.
    private var variantLabel: String?
    /// Source-track details (codec / fps / colour) loaded asynchronously for the stats overlay.
    private var trackCodec = ""
    private var trackFrameRate: Float = 0
    private var trackColorSpace = ""

    /// Called with playback progress in `0...1` as the video advances.
    var onProgress: ((Double) -> Void)?
    /// Called whenever the derived `state` changes.
    var onStateChange: ((VideoState) -> Void)?
    /// Called ~once a second with fresh playback statistics.
    var onStatsChange: ((VideoStats) -> Void)?

    /// Total duration of the current item in seconds, or 0 when unknown.
    var durationSeconds: Double {
        guard let seconds = player?.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 else { return 0 }
        return seconds
    }

    /// Current playhead position in seconds.
    var currentSeconds: Double {
        player?.currentTime().seconds ?? 0
    }

    /// Starts loading `asset`, wiring up state observation, buffering detection and the
    /// end-of-item callback.
    /// - Parameters:
    ///   - autoplay: when `false` the video is loaded paused (the slideshow is paused).
    ///   - forwardBufferDuration: seconds of media to buffer ahead; 0 leaves the system default.
    ///   - maxBitrate: cap on selected bitrate (bits/s); 0 is unlimited.
    ///   - variantLabel: quality label for the stats overlay.
    ///   - onEnded: called when the item plays to the end.
    func start(
        asset: AVURLAsset,
        autoplay: Bool,
        forwardBufferDuration: Double = 30,
        maxBitrate: Double = 0,
        startAtSeconds: Double = 0,
        variantLabel: String? = nil,
        onEnded: @escaping () -> Void
    ) {
        stop()
        hasStartedPlaying = false
        pendingStartSeconds = startAtSeconds
        self.variantLabel = variantLabel
        trackCodec = ""
        trackFrameRate = 0
        trackColorSpace = ""
        loadTrackInfo(from: asset)

        let playerItem = AVPlayerItem(asset: asset)
        if forwardBufferDuration > 0 {
            playerItem.preferredForwardBufferDuration = forwardBufferDuration
        }
        if maxBitrate > 0 {
            playerItem.preferredPeakBitRate = maxBitrate
        }

        let player = AVPlayer(playerItem: playerItem)
        // Prefer building a buffer over starting instantly, so brief network dips don't stall.
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player

        observeStatus(of: playerItem)
        observeTimeControl(of: player)
        observeBuffering(of: playerItem)
        observeProgress()

        if autoplay {
            player.play()
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            onEnded()
        }
        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshState() }
        }

        startWatchdog(for: player)
        refreshState()
    }

    /// Resumes playback.
    func play() {
        guard let player else { return }
        player.play()
        observeProgress()
        startWatchdog(for: player)
        refreshState()
    }

    /// Pauses playback.
    func pause() {
        player?.pause()
        watchdog?.cancel()
        watchdog = nil
        refreshState()
    }

    /// Seeks by a relative number of seconds. Uses zero tolerance so the jump is exactly the
    /// requested amount — the default seek snaps to the nearest keyframe, which for sparse-keyframe
    /// videos lands several seconds off (a "5s" step actually moving 8–9s).
    func seek(seconds: Double) {
        guard let player, let currentItem = player.currentItem else { return }
        let currentTime = player.currentTime()
        let newTime = CMTimeAdd(
            currentTime,
            CMTimeMakeWithSeconds(seconds, preferredTimescale: 600)
        )

        let clampedTime: CMTime = if CMTimeCompare(newTime, .zero) < 0 {
            .zero
        } else if currentItem.duration.isNumeric, CMTimeCompare(newTime, currentItem.duration) > 0 {
            currentItem.duration
        } else {
            newTime
        }

        player.seek(to: clampedTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Seeks to an absolute fraction `0...1` of the duration (used by the scrubber).
    func seek(toFraction fraction: Double) {
        guard let player, durationSeconds > 0 else { return }
        let clamped = min(max(fraction, 0), 1)
        let target = CMTimeMakeWithSeconds(
            durationSeconds * clamped,
            preferredTimescale: 600
        )
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        watchdog?.cancel()
        watchdog = nil
        statusObservation?.invalidate()
        statusObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        likelyToKeepUpObservation?.invalidate()
        likelyToKeepUpObservation = nil
        bufferEmptyObservation?.invalidate()
        bufferEmptyObservation = nil
        removeTimeObserver()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
            self.stalledObserver = nil
        }
        player?.pause()
        player = nil
        state = .loading
        hasStartedPlaying = false
        pendingStartSeconds = 0
    }

    private func observeStatus(of item: AVPlayerItem) {
        statusObservation = item.observe(\.status) { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in
                self.applyPendingStartIfReady()
                self.refreshState()
            }
        }
    }

    /// Once the item is ready to play, seek to any requested start position (a quality switch
    /// resuming mid-video). Runs once — the position is cleared after seeking.
    private func applyPendingStartIfReady() {
        guard pendingStartSeconds > 0,
              let player, player.currentItem?.status == .readyToPlay
        else { return }
        let target = CMTimeMakeWithSeconds(pendingStartSeconds, preferredTimescale: 600)
        pendingStartSeconds = 0
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func observeTimeControl(of player: AVPlayer) {
        timeControlObservation = player.observe(\.timeControlStatus) { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in self.refreshState() }
        }
    }

    private func observeBuffering(of item: AVPlayerItem) {
        likelyToKeepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp) { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in self.refreshState() }
        }
        bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty) { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in self.refreshState() }
        }
    }

    private func refreshState() {
        let newState = currentState()
        guard newState != state else { return }
        state = newState
        onStateChange?(newState)
    }

    private func currentState() -> VideoState {
        guard let player, let item = player.currentItem else { return .loading }

        if item.status == .failed {
            return .failed(
                item.error?.localizedDescription ?? "video failed to load"
            )
        }

        switch player.timeControlStatus {
        case .playing:
            hasStartedPlaying = true
            return .playing
        case .paused:
            return .paused
        case .waitingToPlayAtSpecifiedRate:
            // Once frames have shown, a wait is a mid-stream rebuffer; before that it's the
            // initial load. Either way we keep waiting — the watchdog handles a dead stream.
            return hasStartedPlaying ? .buffering : .loading
        @unknown default:
            return .loading
        }
    }

    /// Samples the buffered lead and live stats once a second. Fails the item only when the
    /// buffer makes no forward progress for `stuckTimeout` while we're trying to play — so a
    /// merely-slow link keeps buffering rather than being skipped.
    private func startWatchdog(for player: AVPlayer) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            var lastBufferedEnd = -1.0
            var lastAdvance = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.player === player, !Task.isCancelled else { return }

                let bufferedEnd = bufferedEndSeconds()
                emitStats(bufferedEnd: bufferedEnd)

                if bufferedEnd > lastBufferedEnd + 0.01 {
                    lastBufferedEnd = bufferedEnd
                    lastAdvance = ContinuousClock.now
                    continue
                }

                // No buffer progress this tick. A paused video legitimately makes none, and a
                // playing one isn't stuck — only worry when we're trying to play but can't.
                if case .failed = state {
                    return
                }
                let trying = player.timeControlStatus != .paused
                if trying,
                   state != .playing,
                   ContinuousClock.now - lastAdvance > Self.stuckTimeout
                {
                    state = .failed("video stalled: the connection is too slow to buffer")
                    onStateChange?(state)
                    return
                }
            }
        }
    }

    /// The playhead-relative end of the currently buffered range, in absolute seconds.
    private func bufferedEndSeconds() -> Double {
        guard let item = player?.currentItem,
              let range = item.loadedTimeRanges.first?.timeRangeValue
        else { return 0 }
        return (range.start + range.duration).seconds
    }

    private func emitStats(bufferedEnd: Double) {
        guard let item = player?.currentItem else { return }
        let event = item.accessLog()?.events.last
        var stats = VideoStats()
        stats.indicatedBitrate = max(event?.indicatedBitrate ?? 0, 0)
        stats.observedBitrate = max(event?.observedBitrate ?? 0, 0)
        stats.resolution = item.presentationSize
        stats.stalls = max(event?.numberOfStalls ?? 0, 0)
        stats.bufferedAhead = max(bufferedEnd - currentSeconds, 0)
        stats.variant = variantLabel
        stats.codec = trackCodec
        stats.frameRate = trackFrameRate
        stats.colorSpace = trackColorSpace
        onStatsChange?(stats)
    }

    /// Loads the source video track's codec, frame rate and colour primaries off the main actor
    /// and stores them for the stats overlay. Best-effort — leaves the fields empty on failure.
    private func loadTrackInfo(from asset: AVURLAsset) {
        Task { [weak self] in
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return }
            let fps = await (try? track.load(.nominalFrameRate)) ?? 0
            let descriptions = await (try? track.load(.formatDescriptions)) ?? []
            guard let description = descriptions.first else {
                await self?.applyTrackInfo(codec: "", frameRate: fps, colorSpace: "")
                return
            }
            let codec = Self.codecName(CMFormatDescriptionGetMediaSubType(description))
            let colorSpace = Self.colorPrimariesName(description)
            await self?.applyTrackInfo(codec: codec, frameRate: fps, colorSpace: colorSpace)
        }
    }

    private func applyTrackInfo(codec: String, frameRate: Float, colorSpace: String) {
        trackCodec = codec
        trackFrameRate = frameRate
        trackColorSpace = colorSpace
    }

    private static func codecName(_ subType: FourCharCode) -> String {
        switch subType {
        case kCMVideoCodecType_H264: "H.264"
        case kCMVideoCodecType_HEVC: "HEVC"
        case kCMVideoCodecType_AV1: "AV1"
        case kCMVideoCodecType_VP9: "VP9"
        case kCMVideoCodecType_MPEG4Video: "MPEG-4"
        default: fourCCString(subType)
        }
    }

    private static func fourCCString(_ code: FourCharCode) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        let scalars = bytes.filter { $0 >= 32 && $0 < 127 }.map { Character(UnicodeScalar($0)) }
        return scalars.isEmpty ? "?" : String(scalars)
    }

    private static func colorPrimariesName(_ description: CMFormatDescription) -> String {
        guard let primaries = CMFormatDescriptionGetExtension(
            description,
            extensionKey: kCMFormatDescriptionExtension_ColorPrimaries
        ) as? String else { return "" }
        if primaries == kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String {
            return "BT.709"
        }
        if primaries == kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String {
            return "BT.2020"
        }
        if primaries == kCMFormatDescriptionColorPrimaries_P3_D65 as String {
            return "P3"
        }
        if primaries == kCMFormatDescriptionColorPrimaries_EBU_3213 as String {
            return "EBU 3213"
        }
        if primaries == kCMFormatDescriptionColorPrimaries_SMPTE_C as String {
            return "SMPTE-C"
        }
        return primaries
    }

    private func observeProgress() {
        removeTimeObserver()
        guard let player else { return }

        let interval = CMTime(
            seconds: 0.05,
            preferredTimescale: CMTimeScale(NSEC_PER_SEC)
        )
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            // The observer is scheduled on the main queue, so we're already on the main actor.
            MainActor.assumeIsolated {
                guard let self, let item = self.player?.currentItem else { return }
                let duration = item.duration.seconds
                guard duration > 0 else { return }
                self.onProgress?(min(time.seconds / duration, 1.0))
            }
        }
    }

    private func removeTimeObserver() {
        if let timeObserverToken {
            player?.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
    }
}
