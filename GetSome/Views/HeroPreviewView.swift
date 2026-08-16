/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A muted, looping preview clip that plays over the hero poster.
*/

import SwiftUI
import AVFoundation

/// A muted preview clip that plays once over the hero poster.
///
/// This is what separates a storefront from a screenshot: the poster paints
/// immediately, and the clip fades in over it once there are frames to show.
/// Every source already scrapes the short hover preview the sites make for
/// their own cards — this is the first place the app plays one.
///
/// **Once, deliberately.** An earlier version looped with `AVPlayerLooper`,
/// which makes a fresh player item per iteration — and a fresh item re-fetches
/// the clip from the network. A banner that quietly re-downloads and re-decodes
/// video forever is a hand-warmer, not a feature. One play per appearance, then
/// back to the poster and the player is released entirely.
///
/// Muted always, and torn down when the banner scrolls away, so it costs
/// nothing while it isn't visible. A preview that fails to load fails into
/// exactly what was there before: the poster.
struct HeroPreviewView: View {
    let url: URL
    let sourceID: String

    @State private var player: AVPlayer?
    @State private var isShowingVideo = false

    var body: some View {
        ZStack {
            if let player {
                PlayerLayerView(player: player)
                    .opacity(isShowingVideo ? 1 : 0)
                    .onReceive(player.publisher(for: \.timeControlStatus)) { status in
                        if status == .playing, !isShowingVideo {
                            withAnimation(.easeIn(duration: 0.4)) { isShowingVideo = true }
                        }
                    }
            }
        }
        .onAppear(perform: start)
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            // Only this player's item — the main player posts the same note.
            guard let item = note.object as? AVPlayerItem, item === player?.currentItem else { return }
            withAnimation(.easeOut(duration: 0.6)) { isShowingVideo = false }
            // Released after the fade so the last frame doesn't cut to black.
            Task {
                try? await Task.sleep(for: .seconds(1))
                stop()
            }
        }
        // The clip is scenery, not content: it duplicates the poster underneath,
        // so VoiceOver shouldn't stop on it.
        .accessibilityHidden(true)
    }

    private func start() {
        guard player == nil else { return }
        let item = AVPlayerItem(asset: PlayerModel.asset(at: url, from: sourceID))
        // A preview is a taste, not a download: don't buffer minutes of it.
        item.preferredForwardBufferDuration = 5
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        self.player = player
        player.play()
    }

    private func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        isShowingVideo = false
    }
}

/// The bare `AVPlayerLayer` host, with no controls to fight the banner's own UI.
private struct PlayerLayerView {
    let player: AVPlayer

    private func configure(_ layer: AVPlayerLayer) {
        layer.player = player
        layer.videoGravity = .resizeAspectFill
    }

    #if os(macOS)
    final class HostView: NSView {
        let playerLayer = AVPlayerLayer()

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            layer = playerLayer
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
    #else
    final class HostView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    #endif
}

#if os(macOS)
extension PlayerLayerView: NSViewRepresentable {
    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        configure(view.playerLayer)
        return view
    }

    func updateNSView(_ view: HostView, context: Context) {
        configure(view.playerLayer)
    }
}
#else
extension PlayerLayerView: UIViewRepresentable {
    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        configure(view.playerLayer)
        return view
    }

    func updateUIView(_ view: HostView, context: Context) {
        configure(view.playerLayer)
    }
}
#endif
