/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
An object that loads and caches the video feeds the app presents.
*/

import Foundation
import SwiftUI

/// The state of a single feed the app has loaded.
struct FeedState {
    var videos: [Video] = []
    var page = 0
    var isLoading = false
    var hasMore = true
    var error: String?
    /// A snapshot is yesterday's page, good enough to draw but not a reason to skip fetching.
    var isSnapshot = false

    var isEmpty: Bool { videos.isEmpty }
}

/// An object that loads and caches the video feeds the app presents.
///
/// Views read the feeds they need through this object rather than making their own
/// requests, so switching tabs doesn't refetch a page the app already has. Feeds
/// from different sources coexist here — a ``Feed`` identifies its own site.
@MainActor
@Observable
final class FeedStore {
    /// A sentinel source ID representing a multi-site search across all sources.
    ///
    /// The same identifier a merged feed carries: both mean "not one site, all of them".
    static let allSitesID = ContentSources.allSitesID

    /// The state of every feed the app has loaded so far, keyed by ``Feed/id``.
    private(set) var feeds = [Feed.ID: FeedState]()

    /// The results of the most recent search.
    private(set) var search = FeedState()

    /// The text of the most recent search.
    private(set) var searchQuery = ""

    /// The source the most recent search ran against.
    private(set) var searchSourceID = ContentSources.primary.id

    private let client: ContentClient
    private var tasks = [Feed.ID: Task<Void, Never>]()
    private var searchTask: Task<Void, Never>?
    private var snapshots: [String: [Video]]

    init(client: ContentClient = .shared) {
        self.client = client
        self.snapshots = FeedSnapshotStore.load()

        for (feedID, videos) in snapshots {
            feeds[feedID] = FeedState(videos: videos, isSnapshot: true)
        }
    }

    /// Returns the state of the specified feed.
    subscript(feed: Feed) -> FeedState {
        feeds[feed.id] ?? FeedState()
    }

    /// Every video the app currently holds, across every feed and the last search.
    ///
    /// Duplicates are expected and wanted: a video that appears in three feeds is
    /// three sightings of its keywords, which is what makes the keyword counts in
    /// ``KeywordsView`` track what's actually prominent.
    var allLoadedVideos: [Video] {
        feeds.values.flatMap(\.videos) + search.videos
    }

    /// Returns a video from any feed the app has loaded.
    func video(with id: VideoID) -> Video? {
        for state in feeds.values {
            if let match = state.videos.first(where: { $0.id == id }) { return match }
        }
        return search.videos.first { $0.id == id }
    }

    /// Loads the first page of a feed, unless the app already has it.
    func loadIfNeeded(_ feed: Feed) {
        let state = self[feed]
        // A snapshot must still refresh to get the latest content.
        guard (state.isEmpty || state.isSnapshot), tasks[feed.id] == nil else { return }
        loadNextPage(of: feed)
    }

    /// Loads the next page of a feed.
    func loadNextPage(of feed: Feed) {
        guard tasks[feed.id] == nil, self[feed].hasMore else { return }

        var state = self[feed]
        state.isLoading = true
        state.error = nil
        feeds[feed.id] = state

        let page = state.page + 1
        tasks[feed.id] = Task { [client] in
            do {
                let videos = try await client.videos(for: feed, page: page)
                merge(videos, into: feed, page: page)
            } catch {
                fail(feed, with: error)
            }
            tasks[feed.id] = nil
        }
    }

    /// Discards a feed's contents and loads its first page again.
    func refresh(_ feed: Feed) async {
        tasks[feed.id]?.cancel()
        tasks[feed.id] = nil
        feeds[feed.id] = FeedState()
        loadNextPage(of: feed)
        await tasks[feed.id]?.value
    }

    // MARK: - Search

    /// Loads the first page of results for the specified text.
    /// - Parameters:
    ///   - query: The text to search for.
    ///   - sourceID: The site to search. Defaults to the site of the previous search.
    func performSearch(_ query: String, in sourceID: String? = nil) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = sourceID ?? searchSourceID
        guard trimmed != searchQuery || source != searchSourceID || search.isEmpty else { return }

        searchTask?.cancel()
        searchTask = nil
        searchQuery = trimmed
        searchSourceID = source
        search = FeedState()

        guard !trimmed.isEmpty else { return }
        loadNextSearchPage()
    }

    /// Loads the first page of results from all searchable sources concurrently.
    ///
    /// Fetches from every source in parallel, tolerating individual failures. Results
    /// are interleaved round-robin so no single source dominates the top.
    /// Only fails the whole search if every source fails.
    /// - Parameter query: The text to search for.
    func performSearchAllSites(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != searchQuery || searchSourceID != Self.allSitesID || search.isEmpty else { return }

        searchTask?.cancel()
        searchTask = nil
        searchQuery = trimmed
        searchSourceID = Self.allSitesID
        search = FeedState()

        guard !trimmed.isEmpty else { return }

        search.isLoading = true
        searchTask = Task { [client] in
            let sources = ContentSources.all.filter(\.supportsSearch)
            guard !sources.isEmpty else { return }

            // Each child answers with a result rather than writing into shared
            // state — the race is resolved by collecting, not by sharing.
            let outcomes = await withTaskGroup(
                of: (Int, Result<[Video], Error>).self,
                returning: [(Int, Result<[Video], Error>)].self
            ) { group in
                for (index, source) in sources.enumerated() {
                    group.addTask {
                        do {
                            return (index, .success(try await client.videos(matching: trimmed, in: source.id, page: 1)))
                        } catch {
                            return (index, .failure(error))
                        }
                    }
                }
                var collected = [(Int, Result<[Video], Error>)]()
                for await outcome in group { collected.append(outcome) }
                return collected
            }
            guard !Task.isCancelled else { return }

            var results = Array(repeating: [Video](), count: sources.count)
            var firstError: Error?
            for (index, outcome) in outcomes {
                switch outcome {
                case .success(let videos): results[index] = videos
                case .failure(let error): if firstError == nil { firstError = error }
                }
            }

            // Interleave round-robin so no site dominates the top of the results.
            var interleaved = [Video]()
            let longest = results.map(\.count).max() ?? 0
            for position in 0..<longest {
                for videos in results where position < videos.count {
                    interleaved.append(videos[position])
                }
            }

            search.isLoading = false
            if interleaved.isEmpty, let firstError {
                // Only fail the whole search when every site failed; one broken
                // site shouldn't empty the other sites' answers.
                search.error = firstError.localizedDescription
            } else {
                search.videos = interleaved
                search.page = 1
                // Paging across sites would need per-site pagination state, so the
                // combined view treats the first page from each as the answer.
                search.hasMore = false
            }
            searchTask = nil
        }
    }

    /// Loads the next page of results for the current search text.
    func loadNextSearchPage() {
        guard !searchQuery.isEmpty, searchTask == nil, search.hasMore else { return }

        search.isLoading = true
        search.error = nil

        let query = searchQuery
        let sourceID = searchSourceID
        let page = search.page + 1
        searchTask = Task { [client] in
            do {
                let videos = try await client.videos(matching: query, in: sourceID, page: page)
                if query == searchQuery && sourceID == searchSourceID {
                    merge(videos, page: page)
                }
            } catch {
                if query == searchQuery && sourceID == searchSourceID {
                    search.isLoading = false
                    search.error = error.localizedDescription
                }
            }
            searchTask = nil
        }
    }

    /// Clears the current search.
    func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchQuery = ""
        search = FeedState()
    }

    // MARK: - Merging results

    private func merge(_ videos: [Video], into feed: Feed, page: Int) {
        var state = self[feed]
        let wasSnapshot = state.isSnapshot

        let additions: [Video]
        if wasSnapshot && page == 1 {
            // Replace snapshot with fresh page 1; a snapshot is yesterday's page,
            // not a real previous pagination state, so it must not carry over into
            // the real fetch sequence.
            state.videos = videos
            additions = videos
        } else {
            // Normal pagination: deduplicate and append new videos.
            let existing = Set(state.videos.map(\.id))
            additions = videos.filter { !existing.contains($0.id) }
            state.videos.append(contentsOf: additions)
        }

        state.page = page
        state.isLoading = false
        state.isSnapshot = false
        // Sites keep serving pages after they run out of new videos, so stop
        // paging when a page adds nothing.
        state.hasMore = !additions.isEmpty
        feeds[feed.id] = state

        // Prefetch posters for upcoming videos so scrolling doesn't show placeholders.
        let toPrefetch = Array(additions.prefix(24))
        Task.detached(priority: .utility) {
            await ContentClient.shared.prefetchPosters(for: toPrefetch)
        }

        // Persist the first page as a snapshot for quick app launch. The write
        // happens off the main actor: it races nothing (the dictionary is copied
        // first) and a scroll should never wait on a cache file.
        if page == 1 {
            snapshots[feed.id] = Array(state.videos.prefix(24))
            let snapshot = snapshots
            Task.detached(priority: .utility) {
                FeedSnapshotStore.save(snapshot)
            }
        }
    }

    private func merge(_ videos: [Video], page: Int) {
        let existing = Set(search.videos.map(\.id))
        let additions = videos.filter { !existing.contains($0.id) }

        search.videos.append(contentsOf: additions)
        search.page = page
        search.isLoading = false
        search.hasMore = !videos.isEmpty && !additions.isEmpty

        // Prefetch posters for upcoming search results so scrolling doesn't show placeholders.
        let toPrefetch = Array(additions.prefix(24))
        Task.detached(priority: .utility) {
            await ContentClient.shared.prefetchPosters(for: toPrefetch)
        }
    }

    private func fail(_ feed: Feed, with error: Error) {
        var state = self[feed]
        state.isLoading = false
        state.error = error.localizedDescription
        // Let the person retry rather than paging past the failure.
        state.hasMore = true
        feeds[feed.id] = state
    }
}
