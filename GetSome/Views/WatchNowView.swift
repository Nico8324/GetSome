/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that presents the app's content library.
*/

import SwiftUI
import SwiftData

/// A view that presents the app's content library.
struct WatchNowView: View {
    @Environment(FeedStore.self) private var feeds

    @State private var navigationPath = [NavigationNode]()
    @State private var isShowingProfile = false
    @Namespace private var namespace

    /// The site a person chose to open with, observed so the screen follows a change.
    @AppStorage(ContentSources.primarySourceKey) private var primarySourceID = ContentSources.all[0].id

    @Query(sort: \SavedVideo.createdAt, order: .reverse)
    private var saved: [SavedVideo]

    /// The site the screen leads with.
    private var source: any ContentSource {
        ContentSources.source(with: primarySourceID) ?? ContentSources.primary
    }

    private var featured: [Video] {
        feeds[source.featuredFeed].videos
    }

    var body: some View {
        // Wrap the content in a vertically scrolling view.
        NavigationStack(path: $navigationPath) {
            ScrollView(showsIndicators: false) {
                VStack {
                    if let heroVideo = featured.first {
                        HeroView(video: heroVideo, namespace: namespace)
                    }

                    // Display a horizontally scrolling list of videos and collections.
                    VStack(spacing: 20) {
                        VideoListView(title: "Trending",
                                      videos: Array(featured.dropFirst().prefix(20)),
                                      cardStyle: .full, namespace: namespace)

                        FeedListView(title: "Collections",
                                     feedList: ContentSources.feeds(in: .collection), namespace: namespace)

                        VideoListView(title: "Just Added",
                                      videos: Array(feeds[source.latestFeed].videos.prefix(20)),
                                      cardStyle: .half, namespace: namespace)

                        FeedListView(title: "Charts",
                                     feedList: ContentSources.feeds(in: .chart), namespace: namespace)

                        if !saved.isEmpty {
                            VideoListView(title: "Saved",
                                          videos: saved.map(\.video),
                                          cardStyle: .half, namespace: namespace)
                        }

                        if featured.isEmpty {
                            FeedStatusView(state: feeds[source.featuredFeed]) {
                                feeds.loadNextPage(of: source.featuredFeed)
                            }
                        }
                    }
                    .padding(.bottom, Constants.outerPadding)
                }
            }
            .scrollClipDisabled()
            .navigationDestinationVideo(in: namespace)
            .toolbarBackground(.hidden)
            #if os(iOS) || os(visionOS)
            .refreshable {
                await feeds.refresh(source.featuredFeed)
            }
            #endif
            .task {
                feeds.loadIfNeeded(source.featuredFeed)
                feeds.loadIfNeeded(source.latestFeed)
            }
            #if os(visionOS)
            .overlay(alignment: .topLeading) {
                ProfileButtonView { isShowingProfile = true }
            }
            #elseif !os(tvOS)
            // Everywhere but tvOS, which has no navigation bar to hold it.
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ProfileButtonView { isShowingProfile = true }
                }
            }
            #endif
            #if !os(tvOS)
            .sheet(isPresented: $isShowingProfile) {
                NavigationStack {
                    ProfileView()
                }
            }
            #endif
        }
    }
}

#Preview(traits: .previewData) {
    WatchNowView()
}
