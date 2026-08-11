/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that displays the videos in a feed.
*/

import SwiftUI

/// A view that displays the videos in a feed.
struct FeedView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(FeedStore.self) private var feeds

    @State private var navigationPath: [NavigationNode]

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
                    Text(feed.name)
                        .font(.title.bold())

                    if ContentSources.hasMultipleSources {
                        Text(feed.sourceName)
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
                        ForEach(state.videos) { video in
                            NavigationLink(value: NavigationNode.video(video.id)) {
                                VideoCardView(video: video, style: .stack)
                            }
                            .accessibilityLabel(video.name)
                            .transitionSource(id: video.id, namespace: namespace)
                            .onAppear {
                                // Load the next page as the list nears its end.
                                if video.id == state.videos.suffix(4).first?.id {
                                    feeds.loadNextPage(of: feed)
                                }
                            }
                        }
                        .buttonStyle(buttonStyle)

                        FeedStatusView(state: state) {
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
