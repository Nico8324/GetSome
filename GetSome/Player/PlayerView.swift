/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that presents the video player.
*/

import SwiftUI
import SwiftData

/// Constants that define the style of controls a player presents.
enum PlayerControlsStyle {
    /// The player uses the system interface that AVPlayerViewController provides.
    case system
    /// The player uses compact controls that display a play/pause button.
    case custom
}

/// A view that presents the video player.
struct PlayerView: View {
    
    static let identifier = "player-view"
    
    let controlsStyle: PlayerControlsStyle
    @State private var showContextualActions = false
    @Environment(PlayerModel.self) private var model

    #if os(iOS)
    @Query(sort: \SavedVideo.createdAt, order: .reverse)
    private var playlist: [SavedVideo]

    /// The next saved video after the one now playing — the same answer the tvOS
    /// and visionOS Up Next tab gives, computed here because the iPhone prompt has
    /// to live at this layer. `AVPlayerViewController`'s content overlay never
    /// receives touches on iOS, so anything tappable must sit above the whole
    /// controller — which is exactly what a SwiftUI `.overlay` here does.
    private var nextVideoInPlaylist: Video? {
        guard let video = model.currentItem,
              let index = playlist.firstIndex(where: { $0.videoID == video.id }),
              playlist.indices.contains(index + 1)
        else { return nil }
        return playlist[index + 1].video
    }
    #endif

    /// Creates a new player view.
    init(controlsStyle: PlayerControlsStyle = .system) {
        self.controlsStyle = controlsStyle
    }

    private var systemPlayerView: some View {
        #if os(macOS)
        // Adds the drag gesture to a transparent overlay and inserts
        // the overlay between the video content and the playback controls.
        let overlay = Color.clear
            .contentShape(.rect)
            .gesture(WindowDragGesture())
            // Enable the window drag gesture to receive events that activate the window.
            .allowsWindowActivationEvents(true)
        return SystemPlayerView(showContextualActions: showContextualActions, overlay: overlay)
        #else
        return SystemPlayerView(showContextualActions: showContextualActions)
        #endif
    }

    var body: some View {
        switch controlsStyle {
        case .system:
            systemPlayerView
                .onChange(of: model.shouldProposeNextVideo) { oldValue, newValue in
                    if oldValue != newValue {
                        showContextualActions = newValue
                    }
                }
                #if os(iOS)
                .overlay {
                    UpNextOverlay(model: model, nextVideo: nextVideoInPlaylist)
                }
                .overlay(alignment: .topTrailing) {
                    QualityMenuButton(model: model)
                }
                #endif
        case .custom:
            #if os(visionOS)
            InlinePlayerView()
            #endif
        }
    }
}

#if os(iOS)
/// A floating menu for capping the stream's resolution while it plays.
///
/// AVKit's own overflow menu accepts no third-party items on iOS, so this is a
/// small button of our own, offset below the system's top controls. Capping only
/// bites on an adaptive stream — a single fixed rendition has nothing to switch —
/// and a cap can only ever lower resolution, so every choice here is safe.
private struct QualityMenuButton: View {
    let model: PlayerModel

    var body: some View {
        Menu {
            Button("Auto") { model.applyQualityCeiling(height: nil) }
            ForEach([1080, 720, 480, 240], id: \.self) { height in
                Button("\(height)p") { model.applyQualityCeiling(height: height) }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.body)
                .padding(10)
                .background(.thinMaterial, in: .circle)
        }
        .padding(.trailing, 16)
        // Below the system's own top-trailing cluster, not on top of it.
        .padding(.top, 72)
        .accessibilityLabel("Maximum Quality")
    }
}
#endif
