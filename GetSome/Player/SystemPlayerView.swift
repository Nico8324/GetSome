/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that provides a platform-specific playback user interface.
*/

import AVKit
import SwiftUI
import SwiftData

#if os(macOS)
// A SwiftUI wrapper on `AVPlayerViewController`.
struct SystemPlayerView<Overlay: View>: NSViewRepresentable {
    @Environment(PlayerModel.self) private var model
    
    let showContextualActions: Bool
    private let overlay: Overlay

    init(showContextualActions: Bool, overlay: Overlay) {
        self.showContextualActions = showContextualActions
        self.overlay = overlay
    }

    final class Coordinator: NSObject, AVPlayerViewDelegate {
        /// The hosting view for the SwiftUI content overlay view.
        weak var overlayHostingView: NSHostingView<Overlay>?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = model.makePlayerUI()
        playerView.controlsStyle = .floating
        playerView.delegate = context.coordinator
        // Create the hosting view for the SwiftUI content overlay view.
        if let contentOverlayView = playerView.contentOverlayView {
            let overlayHostingView = NSHostingView(rootView: overlay)
            context.coordinator.overlayHostingView = overlayHostingView
            // Add the hosting view to the player view's content overlay view.
            contentOverlayView.addSubview(overlayHostingView)
            overlayHostingView.translatesAutoresizingMaskIntoConstraints = false
            overlayHostingView.topAnchor.constraint(equalTo: contentOverlayView.topAnchor).isActive = true
            overlayHostingView.trailingAnchor.constraint(equalTo: contentOverlayView.trailingAnchor).isActive = true
            overlayHostingView.bottomAnchor.constraint(equalTo: contentOverlayView.bottomAnchor).isActive = true
            overlayHostingView.leadingAnchor.constraint(equalTo: contentOverlayView.leadingAnchor).isActive = true
        }
        return playerView
    }

    func updateNSView(_ nsView: NSViewType, context: Context) {
        context.coordinator.overlayHostingView?.rootView = overlay
    }
}
#else
// A SwiftUI wrapper on `AVPlayerViewController`.
struct SystemPlayerView: UIViewControllerRepresentable {
    @Environment(PlayerModel.self) private var model
    
    @Query(sort: \SavedVideo.createdAt, order: .reverse)
    private var playlist: [SavedVideo]

    let showContextualActions: Bool

    init(showContextualActions: Bool) {
        self.showContextualActions = showContextualActions
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {

        // Create a player view controller.
        let controller = model.makePlayerUI()

        // Enable Picture in Picture in iOS and tvOS.
        controller.allowsPictureInPicturePlayback = true

        #if os(visionOS) || os(tvOS)
        // Display an Up Next tab in the player UI.
        if let upNextViewController {
            controller.customInfoViewControllers = [upNextViewController]
        }
        #endif

        // iPhone's Up Next prompt and quality menu are deliberately NOT added here.
        // AVPlayerViewController's content overlay view never receives touches on
        // iOS — the transport chrome intercepts everything — so anything tappable
        // has to live a layer up, in ``PlayerView``'s SwiftUI overlay.

        // Return the configured controller object.
        return controller
    }

    func updateUIViewController(_ controller: UIViewControllerType, context: Context) {
        #if os(visionOS) || os(tvOS)
        Task { @MainActor in
            // Rebuild the list of related videos, if necessary.
            if let upNextViewController {
                controller.customInfoViewControllers = [upNextViewController]
            }

            if let upNextAction, showContextualActions {
                controller.contextualActions = [upNextAction]
            } else {
                controller.contextualActions = []
            }
        }
        #endif

    }

    // A view controller that presents a list of Up Next videos.
    var upNextViewController: UIViewController? {
        guard let video = model.currentItem else { return nil }

        // Find the Up Next list for this video. Return early if there aren't any videos.
        let videos = playlist
            .map(\.video)
            .filter { $0.id != video.id }

        if videos.isEmpty { return nil }

        let view = UpNextView(videos: videos, model: model)
        let controller = UIHostingController(rootView: view)
        // `AVPlayerViewController` uses the view controller's title as the tab name.
        // Specify the view controller's title before setting it as a `customInfoViewControllers` value.
        controller.title = view.title
        // Set the preferred content size for the tab.
        #if os(tvOS)
        controller.preferredContentSize = CGSize(width: 500, height: 250)
        #else
        controller.preferredContentSize = CGSize(width: 600, height: 150)
        #endif

        return controller
    }

    /// The next video after the one currently playing, in the saved list. This is
    /// the single source of truth behind tvOS and visionOS's Up Next tab and
    /// contextual action, and the iPhone overlay reuses it rather than defining a
    /// second notion of "what plays next".
    var nextVideoInPlaylist: Video? {
        guard let video = model.currentItem,
              let index = playlist.firstIndex(where: { $0.videoID == video.id }),
              playlist.indices.contains(index + 1)
        else { return nil }
        return playlist[index + 1].video
    }

    var upNextAction: UIAction? {
        guard let nextVideo = nextVideoInPlaylist else { return nil }

        return UIAction(title: String(localized: "Play Next"), image: UIImage(systemName: "play.fill")) { _ in
            // Load the video for full-window presentation.
            model.loadVideo(nextVideo, presentation: .fullWindow)
        }
    }

}

#endif
