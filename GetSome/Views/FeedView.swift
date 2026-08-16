/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that displays the videos in a feed.
*/

import SwiftUI

/// How a feed's loaded videos should be ordered on screen.
///
/// The sites publish no universal sort parameter, and re-sorting what's loaded
/// costs no request — it's honest about only ordering the pages fetched so far.
enum FeedSort: String, CaseIterable {
    case siteOrder
    case longest
    case newest
    case mostViewed

    /// The localized display name for this sort order.
    var displayName: LocalizedStringKey {
        switch self {
        case .siteOrder: "Site Order"
        case .longest: "Longest"
        case .newest: "Newest"
        case .mostViewed: "Most Viewed"
        }
    }
}

/// A view that displays the videos in a feed.
struct FeedView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(FeedStore.self) private var feeds

    @State private var navigationPath: [NavigationNode]
    @State private var sort: FeedSort = .siteOrder
    /// The one site to show, or nil for all of them. Only merged feeds offer this.
    @State private var siteFilter: String?

    private let feed: Feed
    private let namespace: Namespace.ID

    /// Whether this screen provides its own navigation stack.
    ///
    /// True when it's a tab's root. A category pushed from the categories list is
    /// already inside a stack, and nesting one inside another breaks navigation.
    private let isRoot: Bool

    init(
        feed: Feed,
        namespace: Namespace.ID,
        navigationPath: [NavigationNode]? = nil,
        isRoot: Bool = true
    ) {
        self.feed = feed
        self.namespace = namespace
        self.isRoot = isRoot
        self._navigationPath = State(initialValue: navigationPath ?? [NavigationNode]())
    }

    private var state: FeedState {
        feeds[feed]
    }

    /// The sites a merged feed is currently drawing from, in member order.
    ///
    /// Taken from what's loaded rather than from the registry, so a site that failed
    /// this page doesn't offer a filter that would empty the screen.
    private var representedSites: [String] {
        guard feed.isMerged else { return [] }
        var seen = [String]()
        for video in state.videos where !seen.contains(video.sourceID) {
            seen.append(video.sourceID)
        }
        return seen
    }

    /// The loaded videos the filter admits.
    private var filteredVideos: [Video] {
        guard let siteFilter else { return state.videos }
        return state.videos.filter { $0.sourceID == siteFilter }
    }

    /// The feed's loaded videos in the order selected by the current sort mode.
    private var sortedVideos: [Video] {
        let videos = filteredVideos
        switch sort {
        case .siteOrder:
            return videos
        case .longest:
            return videos.sorted { $0.duration > $1.duration }
        case .newest:
            return videos.sorted { a, b in
                let aDate = a.uploadDate ?? Date.distantPast
                let bDate = b.uploadDate ?? Date.distantPast
                return aDate > bDate
            }
        case .mostViewed:
            return videos.sorted { parseViews($0.views) > parseViews($1.views) }
        }
    }

    /// Parses a formatted view count like "889.7K" or "2.3M" into a numeric value.
    ///
    /// Handles K/M/B multipliers (case-insensitive), strips comma separators, and
    /// returns 0 for unparseable strings.
    private func parseViews(_ viewsString: String) -> Double {
        let cleaned = viewsString.replacingOccurrences(of: ",", with: "")
        let upper = cleaned.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard !upper.isEmpty else { return 0 }

        let multiplier: Double
        let numberStr: String

        if upper.hasSuffix("B") {
            multiplier = 1_000_000_000
            numberStr = String(upper.dropLast())
        } else if upper.hasSuffix("M") {
            multiplier = 1_000_000
            numberStr = String(upper.dropLast())
        } else if upper.hasSuffix("K") {
            multiplier = 1_000
            numberStr = String(upper.dropLast())
        } else {
            multiplier = 1
            numberStr = upper
        }

        return (Double(numberStr.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) * multiplier
    }

    var body: some View {
        if isRoot {
            NavigationStack(path: $navigationPath) { content }
        } else {
            content
        }
    }

    private var content: some View {
        // Wrap the content in a vertically scrolling view.
        Group {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading) {
                    HStack {
                        Text(feed.name)
                            .font(.title.bold())

                        Spacer()

                        // A menu to reorder the displayed videos by various criteria.
                        #if !os(tvOS)
                        // Only on a merged feed: on a single site's feed every
                        // video would pass the filter, so the control would be a
                        // choice with one answer.
                        if feed.isMerged, representedSites.count > 1 {
                            Menu {
                                Picker("Site", selection: $siteFilter) {
                                    Text("All Sites").tag(String?.none)
                                    ForEach(representedSites, id: \.self) { site in
                                        Text(ContentSources.source(with: site)?.displayName ?? site)
                                            .tag(String?.some(site))
                                    }
                                }
                            } label: {
                                Label(
                                    siteFilter.flatMap { ContentSources.source(with: $0)?.displayName }
                                        ?? String(localized: "All Sites"),
                                    systemImage: "line.3.horizontal.decrease"
                                )
                            }
                        }

                        Menu {
                            Picker("Sort", selection: $sort) {
                                ForEach(FeedSort.allCases, id: \.self) { sortOption in
                                    Label(sortOption.displayName, systemImage: "arrow.up.arrow.down")
                                        .tag(sortOption)
                                }
                            }
                        } label: {
                            Label(sort.displayName, systemImage: "arrow.up.arrow.down")
                        }
                        #endif
                    }

                    if ContentSources.hasMultipleSources {
                        Text(feed.sourceCredit)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.tint)
                    }

                    Text(feed.description)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Button("Play", systemImage: "play.fill") {
                        if let firstVideo = state.videos.first {
                            /// Load the media item for full-window presentation.
                            player.loadVideo(firstVideo, presentation: .fullWindow)
                        }
                    }
                    .buttonStyle(CustomButtonStyle())
                    .disabled(state.videos.isEmpty)
                    .padding(.bottom)

                    LazyVStack(spacing: Constants.cardSpacing) {
                        ForEach(sortedVideos) { video in
                            NavigationLink(value: NavigationNode.video(video.id)) {
                                VideoCardView(video: video, style: .stack)
                            }
                            .accessibilityLabel(video.name)
                            .transitionSource(id: video.id, namespace: namespace)
                            .onAppear {
                                // Load the next page as we scroll through the loaded data. We check
                                // the position in the store's unsorted array to trigger pagination
                                // based on actual scrolling depth, not the sort order.
                                if let index = state.videos.firstIndex(of: video) {
                                    let lastFourStartIndex = max(0, state.videos.count - 4)
                                    if index == lastFourStartIndex {
                                        feeds.loadNextPage(of: feed)
                                    }
                                }
                            }
                        }
                        .buttonStyle(buttonStyle)

                        FeedStatusView(state: state) {
                            feeds.loadNextPage(of: feed)
                        }
                    }
                    // A filter can hide the rows that would otherwise ask for the
                    // next page — filter a four-site feed down to one and the
                    // remaining quarter may not even fill the screen, leaving
                    // nothing to scroll to. Keep fetching until it does.
                    .onChange(of: sortedVideos.count, initial: true) { _, count in
                        if siteFilter != nil, count < 8, state.hasMore, !state.isLoading {
                            feeds.loadNextPage(of: feed)
                        }
                    }
                }
                .padding([.horizontal, .bottom], Constants.outerPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .navigationDestinationVideo(in: namespace)
            }
            .scrollClipDisabled()
            .toolbarBackground(.hidden)
            .padding(.top, Constants.categoryTopPadding)
            #if os(iOS) || os(visionOS)
            .refreshable {
                await feeds.refresh(feed)
            }
            #endif
            .task {
                feeds.loadIfNeeded(feed)
            }
            #if os(tvOS)
            .background(Color("tvBackground"))
            #endif
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

/// A view that shows what a feed is doing at the end of its list.
struct FeedStatusView: View {
    let state: FeedState
    let retry: () -> Void

    var body: some View {
        Group {
            if let error = state.error {
                VStack(spacing: Constants.genreSpacing) {
                    Text("Couldn’t load videos")
                        .font(.headline)
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again", action: retry)
                        .buttonStyle(CustomButtonStyle())
                }
            } else if state.isLoading {
                ProgressView()
            } else if state.isEmpty {
                ContentUnavailableView("No videos here", systemImage: "film.stack")
            } else if !state.hasMore {
                Text("That’s everything.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Constants.outerPadding)
    }
}
