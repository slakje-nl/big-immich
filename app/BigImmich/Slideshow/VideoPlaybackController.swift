import AVKit
import ImmichAPI

/// Owns the `AVPlayer` for the currently playing video: its lifecycle, the play-to-end and
/// periodic-time observers, seeking, pause state and the "did it actually start" health check.
///
/// This isolates the observer lifecycle (which previously leaked and crashed on teardown) in
/// one place: every observer added here is removed in `stop()`, so the player is always torn
/// down cleanly. Everything runs on the main actor; the observer callbacks are delivered on
/// the main thread.
@MainActor
final class VideoPlaybackController {
    private(set) var player: AVPlayer?

    private var endObserver: NSObjectProtocol?
    private var timeObserverToken: Any?
    private var pausedByUser = false

    /// Called with playback progress in `0...1` as the video advances.
    var onProgress: ((Double) -> Void)?

    /// Starts loading `url`, wiring up the end-of-item and health-check callbacks.
    /// - Parameters:
    ///   - autoplay: when `false` the video is loaded paused (the slideshow is paused), which
    ///     also marks it user-paused so the health check won't flag it as failed to start.
    ///   - onEnded: called when the item plays to the end.
    ///   - onFailure: called with a user-facing message when the video failed to load or did
    ///     not start playing within the health-check window.
    func start(
        url: URL,
        autoplay: Bool,
        onEnded: @escaping () -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        stop()

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        self.player = player

        if autoplay {
            player.play()
            pausedByUser = false
        } else {
            pausedByUser = true
        }

        scheduleStartHealthCheck(for: player, onFailure: onFailure)
        observeProgress()

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            onEnded()
        }
    }

    /// Resumes playback and clears the user-paused flag.
    func play() {
        guard let player else { return }
        player.play()
        pausedByUser = false
        observeProgress()
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

    /// Pauses playback and records that the pause was intentional, so the start health check
    /// won't misread a paused video as "failed to start".
    func pause() {
        player?.pause()
        pausedByUser = true
    }

    func stop() {
        removeTimeObserver()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        player = nil
    }

    private func scheduleStartHealthCheck(
        for player: AVPlayer,
        onFailure: @escaping (String) -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self, self.player === player else { return }

            if player.status == .failed
                || player.currentItem?.status == .failed
            {
                onFailure("video failed to load")
            } else if player.timeControlStatus != .playing, !pausedByUser {
                onFailure("video did not start playing")
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
