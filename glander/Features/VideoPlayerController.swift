import AppKit
import AVKit

final class VideoPlayerController: NSViewController {
    private let playerView = AVPlayerView()

    override func loadView() {
        let container = NSView()
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.allowsPictureInPicturePlayback = true
        playerView.controlsStyle = .floating
        container.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: container.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        self.view = container
        // Provide a sensible default so the window won't shrink to 0x0
        if self.preferredContentSize == .zero {
            self.preferredContentSize = NSSize(width: 900, height: 600)
        }
    }

    func load(url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        playerView.player = player
        player.play()
    }
}
