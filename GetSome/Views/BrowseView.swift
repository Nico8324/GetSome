/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that displays the videos of a feed in a grid.
*/

import SwiftUI

/// A view that displays the videos of a feed in a grid.
///
/// When the app browses more than one site, a site picker appears above the feed
/// picker and the feeds below it belong to whichever site is selected.
struct BrowseView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(FeedStore.self) private var feeds

    @Namespace private var namespace

    @State private var navigationPath = [NavigationNode]()
    @State private var selectedSourceID = ContentSources.hasMultipleSources
        ? ContentSources.allSitesID
        : ContentSources.primary.id
    @State private var selectedFeedID = ContentSources.mergedFeeds.first?.id
        ?? ContentSources.primary.feeds[0].id

    /// Whether the site picker is on the cross-site option rather than one site.
    private var isBrowsingAllSites: Bool {
        selectedSourceID == ContentSources.allSitesID
    }

    private var availableFeeds: [Feed] {
        if isBrowsingAllSites {
            return ContentSources.mergedFeeds
        }
        return ContentSources.source(with: selectedSourceID)?.feeds ?? []
    }

    private var selectedFeed: Feed? {
        ContentSources.feed(with: selectedFeedID) ?? availableFeeds.first
    }

    private var state: FeedState {
        selectedFeed.map { feeds[$0] } ?? FeedState()
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            // Wrap the content in a vertically scrolling view.
            ScrollView(showsIndicators: false) {
                VStack {
                    if ContentSources.hasMultipleSources {
                        sourcePicker
                    }
                    feedPicker

                    VideoGridView(videos: state.videos, namespace: namespace) { video in
                        // Load the next page as the grid nears its end.
                        if let feed = selectedFeed, video.id == state.videos.suffix(6).first?.id {
                            feeds.loadNextPage(of: feed)
                        }
                    }

                    FeedStatusView(state: state) {
                        if let feed = selectedFeed { feeds.loadNextPage(of: feed) }
                    }
                }
                .navigationDestinationVideo(in: namespace)
                .padding(Constants.outerPadding)
            }
            .scrollClipDisabled()
            #if os(iOS) || os(visionOS)
            .refreshable {
                if let feed = selectedFeed { await feeds.refresh(feed) }
            }
            #endif
            .task {
                if let feed = selectedFeed { feeds.loadIfNeeded(feed) }
            }
        }
    }

    private var sourcePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                // First, and the one the screen opens on: the shelves elsewhere in
                // the app are cross-site now, so arriving here at a single site
                // would read as the app narrowing without being asked. Picking a
                // site is still one tap away, which is what this screen is for.
                Button("All Sites") {
                    selectedSourceID = ContentSources.allSitesID
                    if let first = ContentSources.mergedFeeds.first {
                        selectedFeedID = first.id
                        feeds.loadIfNeeded(first)
                    }
                }
                .buttonStyle(PickerButtonStyle(isSelected: isBrowsingAllSites))

                ForEach(ContentSources.all, id: \.id) { source in
                    Button(source.displayName) {
                        selectedSourceID = source.id
                        // Move to the new site's first feed.
                        if let first = source.feeds.first {
                            selectedFeedID = first.id
                            feeds.loadIfNeeded(first)
                        }
                    }
                    .buttonStyle(PickerButtonStyle(isSelected: selectedSourceID == source.id))
                }
            }
        }
        .scrollClipDisabled()
        .padding(.bottom, Constants.genreSpacing)
    }

    private var feedPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(availableFeeds) { feed in
                    Button(feed.name) {
                        selectedFeedID = feed.id
                        feeds.loadIfNeeded(feed)
                    }
                    .buttonStyle(PickerButtonStyle(isSelected: selectedFeedID == feed.id))
                }

                // These sit with the feeds because they're the same kind of choice,
                // but carry icons: they push a list rather than filtering in place.
                if ContentSources.source(with: selectedSourceID)?.hasCategories == true {
                    NavigationLink(value: NavigationNode.categories(sourceID: selectedSourceID)) {
                        Label("Categories", systemImage: "tag")
                    }
                    .buttonStyle(PickerButtonStyle(isSelected: false))
                }

                // Not per-site, unlike categories: keywords are gathered from
                // everything loaded, whichever site published them.
                NavigationLink(value: NavigationNode.keywords) {
                    Label("Keywords", systemImage: "number")
                }
                .buttonStyle(PickerButtonStyle(isSelected: false))
            }
        }
        .scrollClipDisabled()
        .padding(.bottom)
    }
}

/// A view that lays video cards out in an adaptive grid.
struct VideoGridView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let videos: [Video]
    let namespace: Namespace.ID
    /// An action the view performs as each card appears, so a caller can page.
    var onAppear: (Video) -> Void = { _ in }

    // Adapt the number columns based on platform and size class.
    private var columns: [GridItem] {
        let gridItem = GridItem(.flexible(), spacing: Constants.cardSpacing)
        let count = horizontalSizeClass == .compact ? Constants.libraryColumnCountCompact : Constants.libraryColumnCount
        return [GridItem](repeating: gridItem, count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Constants.cardSpacing) {
            ForEach(videos) { video in
                NavigationLink(value: NavigationNode.video(video.id)) {
                    VideoCardView(video: video, style: .grid)
                }
                .transitionSource(id: video.id, namespace: namespace)
                .accessibilityLabel(video.name)
                .buttonStyle(buttonStyle)
                .onAppear { onAppear(video) }
            }
        }
    }

    var buttonStyle: some PrimitiveButtonStyle {
        #if os(tvOS)
        .card
        #else
        .plain
        #endif
    }
}

#Preview(traits: .previewData) {
    BrowseView()
}
