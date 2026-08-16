/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that presents a horizontally scrollable list of collections.
*/

import SwiftUI

/// A view that presents a horizontally scrollable list of collections.
///
/// Each card shows the poster of the first video currently in that feed, so the
/// artwork reflects what the collection actually contains. Feeds may come from
/// different sources; each card names its site when there's more than one.
struct FeedListView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(FeedStore.self) private var feeds

    var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    let title: LocalizedStringKey
    let feedList: [Feed]
    let namespace: Namespace.ID

    /// The width of one card, which also fixes the poster's height.
    private var cardWidth: Double {
        isCompact ? Constants.compactVideoCardWidth : Constants.videoCardWidth
    }

    /// The video whose poster stands in for each feed, keyed by feed.
    ///
    /// Picked left to right, skipping anything an earlier card already shows. Feeds
    /// that overlap — and merged feeds overlap constantly, since the same video is
    /// often both the most popular and the newest — otherwise drew the identical
    /// poster twice in a row, which reads as a bug rather than as a coincidence.
    private var covers: [Feed.ID: Video] {
        var used = Set<URL>()
        var result = [Feed.ID: Video]()
        for feed in feedList {
            let videos = feeds[feed].videos
            let choice = videos.first { $0.thumbnailURL.map { !used.contains($0) } ?? false }
                ?? videos.first
            if let choice {
                result[feed.id] = choice
                if let url = choice.thumbnailURL { used.insert(url) }
            }
        }
        return result
    }

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Constants.cardSpacing) {
                    let covers = covers
                    ForEach(feedList) { feed in
                        NavigationLink(value: NavigationNode.feed(feed.id)) {
                            card(for: feed, cover: covers[feed.id])
                            #if os(iOS) || os(visionOS)
                            .hoverEffect()
                            #endif
                        }
                        .accessibilityLabel(feed.qualifiedName)
                        .buttonStyle(buttonStyle)
                        .transitionSource(id: feed.id, namespace: namespace)
                    }
                }
                .padding(.vertical, Constants.listTitleVerticalPadding)
                .padding(.leading, Constants.outerPadding)
            }
            .scrollClipDisabled()
        } header: {
            Text(title)
                .font(.title3.bold())
                .padding(.leading, Constants.outerPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .task {
            // Load just enough of each feed to draw its cover.
            for feed in feedList {
                feeds.loadIfNeeded(feed)
            }
        }
    }

    /// One collection card.
    ///
    /// Both the poster and the title are given the same explicit width rather than
    /// being sized by their content. Left to infer it, the title ended up centred on
    /// a collapsed frame and rendered half off the card.
    private func card(for feed: Feed, cover: Video?) -> some View {
        VStack(alignment: .leading, spacing: Constants.genreSpacing) {
            posterBody(for: feed, cover: cover)
                .frame(width: cardWidth, height: cardWidth * 9 / 16)
                .clipShape(.rect(cornerRadius: Constants.cornerRadius))

            Text(feed.qualifiedName)
                #if os(visionOS)
                .font(.title3)
                #else
                .font(.body)
                #endif
                .lineLimit(1)
                .frame(width: cardWidth, alignment: .leading)
        }
    }

    private func posterBody(for feed: Feed, cover: Video?) -> some View {
        // Both decorations go in overlays rather than a ZStack. A LinearGradient
        // has no size of its own, so in a stack it expands past the image and
        // becomes what drives the card's layout — which pushed the title off its
        // leading edge and made these cards taller than the video rows.
        // The cover video's own site, not the feed's: a merged feed belongs to no
        // single site, and the poster is fetched with that site's headers.
        PosterImageView(url: cover?.thumbnailURL, sourceID: cover?.sourceID ?? feed.sourceID)
            .aspectRatio(16 / 9, contentMode: .fill)
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.55), .black.opacity(0.15)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            }
            .overlay {
                Image(systemName: feed.icon)
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                    .shadow(radius: 6)
            }
            .clipped()
    }

    var buttonStyle: some PrimitiveButtonStyle {
        #if os(tvOS)
        .card
        #else
        .plain
        #endif
    }
}
