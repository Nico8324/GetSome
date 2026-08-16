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
    @State private var heroIndex = 0
    @Namespace private var namespace

    /// The site a person chose to open with, observed so the screen follows a change.
    @AppStorage(ContentSources.primarySourceKey) private var primarySourceID = ContentSources.all[0].id

    @Query(sort: \SavedVideo.createdAt, order: .reverse)
    private var saved: [SavedVideo]

    /// The site the screen leads with.
    private var source: any ContentSource {
        ContentSources.source(with: primarySourceID) ?? ContentSources.primary
    }

    /// The feed behind the hero and the Trending row.
    ///
    /// The merged one when the app browses several sites: the top of this screen is
    /// the app's front page, and filling it from a single site meant three of the
    /// four went unseen unless you went looking. The chosen site still leads the
    /// merge — see ``ContentSources/members(of:)`` — so the preference is visible in
    /// what comes first rather than in what's excluded.
    private var featuredFeed: Feed {
        ContentSources.mergedFeeds.first { $0.kind == .popular } ?? source.featuredFeed
    }

    /// The feed behind the Just Added row, merged on the same terms.
    private var latestFeed: Feed {
        ContentSources.mergedFeeds.first { $0.kind == .latest } ?? source.latestFeed
    }

    private var featured: [Video] {
        feeds[featuredFeed].videos
    }

    var body: some View {
        // Wrap the content in a vertically scrolling view.
        NavigationStack(path: $navigationPath) {
            ScrollView(showsIndicators: false) {
                VStack {
                    // The hero banner rotates through the first few featured videos, advancing
                    // every eight seconds with a crossfade. If the featured feed updates and
                    // shrinks while rotating, the hero falls back to the first available video
                    // to avoid displaying nothing.
                    if let heroVideo = heroIndex < featured.count ? featured[heroIndex] : featured.first {
                        HeroView(video: heroVideo, namespace: namespace)
                            .id(heroVideo.id)
                            .transition(.opacity)
                    }

                    // Display a horizontally scrolling list of videos and collections.
                    VStack(spacing: 20) {
                        VideoListView(title: "Trending",
                                      videos: Array(featured.dropFirst().prefix(20)),
                                      cardStyle: .full, namespace: namespace)

                        ContinueWatchingView(namespace: namespace)

                        FeedListView(title: "Collections",
                                     feedList: ContentSources.feeds(in: .collection), namespace: namespace)

                        VideoListView(title: "Just Added",
                                      videos: Array(feeds[latestFeed].videos.prefix(20)),
                                      cardStyle: .half, namespace: namespace)

                        FeedListView(title: "Charts",
                                     feedList: ContentSources.feeds(in: .chart), namespace: namespace)

                        if !saved.isEmpty {
                            VideoListView(title: "Saved",
                                          videos: saved.map(\.video),
                                          cardStyle: .half, namespace: namespace)
                        }

                        if featured.isEmpty {
                            FeedStatusView(state: feeds[featuredFeed]) {
                                feeds.loadNextPage(of: featuredFeed)
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
                // Both feeds this screen draws from, or "Just Added" stays stale
                // while the rest of the screen visibly updates.
                async let featured: Void = feeds.refresh(featuredFeed)
                async let latest: Void = feeds.refresh(latestFeed)
                _ = await (featured, latest)
            }
            #endif
            .task {
                feeds.loadIfNeeded(featuredFeed)
                feeds.loadIfNeeded(latestFeed)
            }
            .task(id: featured.isEmpty) {
                // Rotate the hero banner through the first five featured videos every
                // eight seconds. The animation dependency tracks featured emptiness, so
                // the rotation stops and resets if the feed clears out. If the feed
                // shrinks while rotating, heroIndex might go out of bounds, but the
                // display view handles that by falling back to the first video.
                guard !featured.isEmpty else { return }

                // One full cycle, then rest. Each rotation starts a fresh preview
                // download and decode, so an unbounded loop kept the radio and the
                // video decoder warm for as long as the screen was open — which a
                // phone reports as heat. A single tour of the top five is the wow;
                // returning to the screen starts a new tour.
                for _ in 0..<min(featured.count, 5) {
                    // A thrown CancellationError must end the loop: swallowing it
                    // with try? would spin this task at full speed the moment the
                    // view disappears, because every later sleep returns instantly.
                    do { try await Task.sleep(for: .seconds(8)) } catch { break }
                    guard !featured.isEmpty else { break }

                    withAnimation(.easeInOut(duration: 0.8)) {
                        heroIndex = (heroIndex + 1) % min(featured.count, 5)
                    }
                }
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
