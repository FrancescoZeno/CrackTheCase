import SwiftUI
import UIKit
import AVFoundation

/// A quiet, gapless-looping video meant to sit *behind* other content (the
/// home screen's cinematic backdrop) — unlike `introVideoView`'s
/// `VideoPlayer`, this has no playback chrome, controls, or one-shot
/// "advance on finish" behavior. Built on `AVQueuePlayer` + `AVPlayerLooper`
/// rather than restarting a plain `AVPlayer` from
/// `.AVPlayerItemDidPlayToEndTime` (the pattern `introVideoView` uses),
/// since that approach has a visible stutter/black-frame gap between loops
/// that would be very noticeable on a screen sitting idle in the background.
struct LoopingVideoBackground: UIViewRepresentable {
    let resourceName: String
    let fileExtension: String

    init(_ resourceName: String, fileExtension: String = "mp4") {
        self.resourceName = resourceName
        self.fileExtension = fileExtension
    }

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension) else {
            return view
        }

        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.volume = 0.2
        context.coordinator.looper = AVPlayerLooper(player: queuePlayer, templateItem: item)

        view.playerLayer.player = queuePlayer
        view.playerLayer.videoGravity = .resizeAspectFill
        queuePlayer.play()
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Owns the `AVPlayerLooper`, which must be kept alive for as long as
    /// looping should continue — letting it deallocate silently stops the
    /// loop.
    final class Coordinator {
        var looper: AVPlayerLooper?
    }

    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
