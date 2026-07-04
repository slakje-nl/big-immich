import AVKit
import SwiftUI

/// A minimal video surface that renders an `AVPlayer` through an `AVPlayerLayer`, with no
/// system transport controls.
///
/// SwiftUI's `VideoPlayer` wraps `AVPlayerViewController`, whose built-in transport intercepts
/// the remote's play/pause button and competes with the slideshow's own handling (causing an
/// out-of-phase, multi-press pause). Owning the layer directly makes the slideshow's
/// `.onPlayPauseCommand` the single source of truth for play/pause; seeking stays on the
/// up/down remote gestures and progress is drawn by the slideshow's own bar.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context _: Context) -> PlayerContainerView {
        PlayerContainerView(player: player)
    }

    func updateUIView(_ uiView: PlayerContainerView, context _: Context) {
        uiView.player = player
    }
}

/// A `UIView` backed by an `AVPlayerLayer`, so the video fills the view and resizes with it.
final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    /// Always an AVPlayerLayer thanks to `layerClass`; cast optionally to keep the linter happy.
    private var playerLayer: AVPlayerLayer? {
        layer as? AVPlayerLayer
    }

    var player: AVPlayer? {
        get { playerLayer?.player }
        set { playerLayer?.player = newValue }
    }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer?.player = player
        playerLayer?.videoGravity = .resizeAspect
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
