/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A horizontally scrollable list of videos the user has partially watched.
*/

import SwiftUI
import SwiftData

/// A view displaying videos that the user has started but not completed.
///
/// The list pulls from the app's local watch history, filtering to entries where
/// playback was paused between 30 seconds in and a minute from the end. This
/// focuses on videos worth resuming, avoiding ones that were barely started or
/// have too little left to warrant resuming. The list displays the most recently
/// watched entries first, limited to ten, and renders nothing at all when there
/// are no candidates — rather than orphaning a header over an empty row.
struct ContinueWatchingView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(TranslationStore.self) private var translator

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    let namespace: Namespace.ID

    /// All watched videos, sorted newest first. SwiftData calls this on every
    /// change to the model, so the list stays current as playback position updates.
    @Query(sort: \WatchedVideo.watchedAt, order: .reverse)
    private var allWatched: [WatchedVideo]

    /// Videos the user has watched enough of to resume, filtered and limited.
    private var continuableVideos: [WatchedVideo] {
        allWatched
            .filter { entry in
                // Skip videos with no meaningful duration or progress recorded.
                guard entry.duration > 0 else { return false }
                // Include videos paused at least 30 seconds in (past the intro bump).
                guard entry.playbackPosition > 30 else { return false }
                // Include only if there's a minute or more left to watch. A video
                // with barely a minute remaining still beats stopping and restarting.
                guard entry.playbackPosition < entry.duration - 60 else { return false }
                return true
            }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        // Show the list only when there are videos to display. An empty query
        // result does not render a header — it renders nothing. This avoids the
        // visual noise of a section header floating over blank space while the
        // history stays empty.
        if !continuableVideos.isEmpty {
            list
        }
    }

    private var list: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Constants.cardSpacing) {
                    ForEach(Array(continuableVideos), id: \.self) { entry in
                        NavigationLink(value: NavigationNode.video(entry.video.id)) {
                            // The video card with a progress bar overlaid at the bottom.
                            // The bar fades out below the rounded corners.
                            ZStack(alignment: .bottomLeading) {
                                VideoCardView(video: entry.video, style: .half)

                                // Progress bar at the card's bottom, inset slightly to align
                                // with the rounded corners.
                                WatchProgressBar(progress: Double(entry.playbackPosition) / Double(entry.duration))
                                    .frame(height: 3)
                                    .padding(8)
                            }
                            .clipShape(.rect(cornerRadius: Constants.cornerRadius))
                        }
                        .accessibilityLabel(entry.video.name)
                        .transitionSource(id: entry.video.id, namespace: namespace)
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, Constants.outerPadding)
            }
            .scrollClipDisabled()
        } header: {
            Text("Continue Watching")
                .font(.title3.bold())
                .padding(.vertical, Constants.listTitleVerticalPadding)
                .padding(.leading, Constants.outerPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}

#Preview(traits: .previewData) {
    NavigationStack {
        ScrollView {
            VStack(spacing: 20) {
                ContinueWatchingView(namespace: Namespace().wrappedValue)
            }
            .padding(.bottom, Constants.outerPadding)
        }
    }
}
