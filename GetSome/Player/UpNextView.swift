/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that displays a list of videos related to the currently playing video.
*/

import SwiftUI

/// A view that displays a list of videos related to the currently playing video.
struct UpNextView: View {
    let title = String(localized: "Up Next", comment: "Used as window title")
    let videos: [Video]
    let model: PlayerModel

    @Namespace private var namespace

    var body: some View {
        VideoListView(videos: videos, cardStyle: .upNext, namespace: namespace) { video in
            model.loadVideo(video, presentation: .fullWindow)
        }
    }
}

#if os(iOS)
/// The overlay iPhone uses in place of the Up Next tab tvOS and visionOS show.
///
/// AVPlayerViewController's `customInfoViewControllers` — the tab tvOS and visionOS
/// use to show ``UpNextView`` — has no iOS equivalent, and without it an iPhone
/// viewer got nothing at the end of a video. This draws directly on the player's
/// content overlay instead: a small "Play Next" prompt as the video winds down, and
/// a full countdown once it actually ends.
struct UpNextOverlay: View {
    let model: PlayerModel

    /// The next video to propose, found the same way tvOS and visionOS find the one
    /// they show in their Up Next tab and contextual action.
    let nextVideo: Video?

    /// The video whose countdown a person cancelled, so a cancelled countdown
    /// doesn't reappear for that same video. `isPlaybackComplete` stays `true` after
    /// a video ends until the next `loadVideo` call, so without this guard the
    /// countdown would come right back the moment the view re-evaluates its body.
    @State private var cancelledVideoID: VideoID?

    private var isCancelled: Bool {
        cancelledVideoID != nil && cancelledVideoID == model.currentItem?.id
    }

    var body: some View {
        Group {
            if let nextVideo, model.isPlaybackComplete, !isCancelled {
                countdownOverlay(for: nextVideo)
            } else if let nextVideo, model.shouldProposeNextVideo, !model.isPlaybackComplete {
                compactOverlay(for: nextVideo)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.easeInOut, value: model.isPlaybackComplete)
        .animation(.easeInOut, value: model.shouldProposeNextVideo)
        .onChange(of: model.currentItem?.id) {
            // A freshly loaded video hasn't been cancelled by anyone yet.
            cancelledVideoID = nil
        }
    }

    /// A compact "Play Next" prompt shown as the current video nears its end.
    private func compactOverlay(for video: Video) -> some View {
        Button {
            model.loadVideo(video, presentation: .fullWindow)
        } label: {
            HStack(spacing: 12) {
                PosterImageView(url: video.thumbnailURL, sourceID: video.sourceID)
                    .frame(width: 80, height: 45)
                    .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Play Next")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(video.name)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Constants.cornerRadius + 2))
        }
        .buttonStyle(.plain)
        .padding([.bottom, .trailing], 16)
        .transition(.opacity)
    }

    /// A full "Up Next in 5" countdown shown once the current video finishes,
    /// which auto-plays `video` when it reaches zero unless cancelled first.
    private func countdownOverlay(for video: Video) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PosterImageView(url: video.thumbnailURL, sourceID: video.sourceID)
                    .frame(width: 120, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius))
                VStack(alignment: .leading, spacing: 4) {
                    CountdownText(video: video, onComplete: { model.loadVideo(video, presentation: .fullWindow) })
                    Text(video.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack {
                Button(role: .cancel) {
                    cancelledVideoID = model.currentItem?.id
                } label: {
                    Text("Cancel")
                }
                Spacer()
                Button {
                    model.loadVideo(video, presentation: .fullWindow)
                } label: {
                    Text("Play Next")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(maxWidth: 320)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Constants.cornerRadius + 4))
        .padding([.bottom, .trailing], 16)
        .transition(.opacity)
    }
}

/// A label that counts down from 5 to 0 and calls `onComplete` once, when it
/// reaches zero. A separate view so its own `.task(id:)` lifetime — tied to the
/// video it's counting down for — starts and stops independently of the rest of
/// ``UpNextOverlay``, and is cancelled automatically by SwiftUI when the countdown
/// is dismissed (Cancel removes this view from the hierarchy).
private struct CountdownText: View {
    let video: Video
    let onComplete: () -> Void

    @State private var secondsRemaining = 5

    var body: some View {
        Text("Up Next in \(secondsRemaining)")
            .font(.headline)
            .contentTransition(.numericText(countsDown: true))
            .task(id: video.id) {
                secondsRemaining = 5
                while secondsRemaining > 0 {
                    do {
                        try await Task.sleep(for: .seconds(1))
                    } catch {
                        // Cancelled — the countdown was dismissed or superseded.
                        return
                    }
                    withAnimation { secondsRemaining -= 1 }
                }
                onComplete()
            }
    }
}
#endif
