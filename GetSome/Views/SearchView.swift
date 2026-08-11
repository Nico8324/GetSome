/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that searches a source's catalog.
*/

import SwiftUI

/// A view that searches a source's catalog.
///
/// A search runs against one site at a time. When the app browses more than one,
/// a picker chooses which — and re-runs the current text against the new site.
struct SearchView: View {
    @Environment(FeedStore.self) private var feeds

    @Namespace private var namespace
    @State private var navigationPath = [NavigationNode]()
    @State private var query = ""
    @State private var sourceID = ContentSources.primary.id

    private var searchableSources: [any ContentSource] {
        ContentSources.all.filter(\.supportsSearch)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading) {
                    if searchableSources.count > 1 {
                        sourcePicker
                    }

                    if feeds.searchQuery.isEmpty {
                        ContentUnavailableView(
                            "Search",
                            systemImage: "magnifyingglass",
                            description: Text("Find videos by title, performer, or keyword.")
                        )
                        .padding(.top, Constants.outerPadding * 3)
                    } else {
                        VideoGridView(videos: feeds.search.videos, namespace: namespace) { video in
                            // Load the next page as the grid nears its end.
                            if video.id == feeds.search.videos.suffix(6).first?.id {
                                feeds.loadNextSearchPage()
                            }
                        }

                        FeedStatusView(state: feeds.search) {
                            feeds.loadNextSearchPage()
                        }
                    }
                }
                .padding(Constants.outerPadding)
                .navigationDestinationVideo(in: namespace)
            }
            .scrollClipDisabled()
            .navigationTitle("Search")
            #if !os(tvOS)
            .searchable(text: $query, prompt: Text("Search videos"))
            #endif
            .onSubmit(of: .search) {
                feeds.performSearch(query, in: sourceID)
            }
            .onChange(of: query) { _, newValue in
                if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    feeds.clearSearch()
                }
            }
            #if os(tvOS)
            .onAppear {
                // tvOS doesn't offer a search field in this position, so show a
                // popular starting point instead of an empty screen.
                if feeds.searchQuery.isEmpty {
                    feeds.performSearch("hd", in: sourceID)
                }
            }
            #endif
        }
    }

    private var sourcePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(searchableSources, id: \.id) { source in
                    Button(source.displayName) {
                        sourceID = source.id
                        // Re-run whatever a person already typed against the new site.
                        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                            feeds.performSearch(query, in: source.id)
                        }
                    }
                    .buttonStyle(PickerButtonStyle(isSelected: sourceID == source.id))
                }
            }
        }
        .scrollClipDisabled()
        .padding(.bottom, Constants.genreSpacing)
    }
}

/// A view that displays the results for a fixed search, such as a keyword someone taps.
struct SearchResultsView: View {
    let sourceID: String
    let query: String
    let namespace: Namespace.ID

    @State private var results = FeedState()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading) {
                VideoGridView(videos: results.videos, namespace: namespace)

                FeedStatusView(state: results) {
                    Task { await load() }
                }
            }
            .padding(Constants.outerPadding)
        }
        .scrollClipDisabled()
        .navigationTitle(query)
        .task { await load() }
    }

    private func load() async {
        guard results.isEmpty else { return }
        results.isLoading = true
        results.error = nil
        do {
            results.videos = try await ContentClient.shared.videos(matching: query, in: sourceID)
            results.isLoading = false
            results.hasMore = false
        } catch {
            results.isLoading = false
            results.error = error.localizedDescription
        }
    }
}

#Preview(traits: .previewData) {
    SearchView()
}
