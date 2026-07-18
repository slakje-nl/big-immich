import AVKit
import ImmichAPI

/// Observed playback state of the current video, derived from `AVPlayer`/`AVPlayerItem`.
enum VideoState: Equatable {
    /// Buffering or waiting to start (`timeControlStatus == .waitingToPlayAtSpecifiedRate`).
    case loading
    case playing
    case paused
    /// The item failed to load, or never started within the stall window.
    case failed(String)
}

/// Owns the `AVPlayer` for the currently playing video: its lifecycle, the play-to-end and
/// periodic-time observers, seeking, and playback state.
///
/// Playback state is read from the player itself — `AVPlayerItem.status` (real load failures,
/// with the underlying error) and `AVPlayer.timeControlStatus` (playing / paused / buffering)
/// — instead of guessing with a fixed timer. A single generous stall guard still advances a
/// stream that never fails but also never starts. Every observer added here is torn down in
/// `stop()`. Everything runs on the main actor; KVO callbacks hop to it since AVFoundation may
/// deliver them off the main thread.
@MainActor
final class VideoPlaybackController {
    private static let stallTimeout: Duration = .seconds(15)

    private(set) var player: AVPlayer?
    private(set) var state: VideoState = .loading

    private var endObserver: NSObjectProtocol?
    private var timeObserverToken: Any?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var stallGuard: Task<Void, Never>?

    /// Called with playback progress in `0...1` as the video advances.
    var onProgress: ((Double) -> Void)?
    /// Called whenever the derived `state` changes.
    var onStateChange: ((VideoState) -> Void)?

    /// Starts loading `url`, wiring up state observation and the end-of-item callback.
    /// - Parameters:
    ///   - autoplay: when `false` the video is loaded paused (the slideshow is paused).
    ///   - onEnded: called when the item plays to the end.
    func start(
        asset: AVURLAsset,
        autoplay: Bool,
        onEnded: @escaping () -> Void
    ) {
        stop()

        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        // Prefer building a buffer over starting instantly, so brief network dips don't stall.
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player

        observeStatus(of: playerItem)
        observeTimeControl(of: player)
        observeProgress()

        if autoplay {
            player.play()
            scheduleStallGuard(for: player)
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            onEnded()
        }

        refreshState()
    }

    /// Resumes playback.
    func play() {
        guard let player else { return }
        player.play()
        observeProgress()
        scheduleStallGuard(for: player)
        refreshState()
    }

    /// Pauses playback.
    func pause() {
        player?.pause()
        stallGuard?.cancel()
        stallGuard = nil
        refreshState()
    }

    func seek(seconds: Double) {
        guard let player, let currentItem = player.currentItem else { return }
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

    func stop() {
        stallGuard?.cancel()
        stallGuard = nil
        statusObservation?.invalidate()
        statusObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        removeTimeObserver()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        player = nil
        state = .loading
    }

    private func observeStatus(of item: AVPlayerItem) {
        statusObservation = item.observe(\.status) { [weak self] _, _ in
            Task { @MainActor in self?.refreshState() }
        }
    }

    private func observeTimeControl(of player: AVPlayer) {
        timeControlObservation = player.observe(\.timeControlStatus) { [weak self] _, _ in
            Task { @MainActor in self?.refreshState() }
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
            return .playing
        case .paused:
            return .paused
        case .waitingToPlayAtSpecifiedRate:
            return .loading
        @unknown default:
            return .loading
        }
    }

    /// Fallback for a stream that never emits `.failed` but also never starts: after a generous
    /// window, if we're still `.loading` (not paused, not playing), treat it as failed to start.
    private func scheduleStallGuard(for player: AVPlayer) {
        stallGuard?.cancel()
        stallGuard = Task { [weak self] in
            try? await Task.sleep(for: Self.stallTimeout)
            guard let self, !Task.isCancelled, self.player === player else { return }
            if state == .loading {
                state = .failed("video did not start playing")
                onStateChange?(state)
            }
        }
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
            if let duration = player.currentItem?.duration.seconds,
               duration > 0
            {
                self?.onProgress?(min(time.seconds / duration, 1.0))
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
