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

    init(client: ContentClient = .shared) {
        self.client = client
    }

    /// Returns the state of the specified feed.
    subscript(feed: Feed) -> FeedState {
        feeds[feed.id] ?? FeedState()
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
        guard self[feed].isEmpty, tasks[feed.id] == nil else { return }
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
        let existing = Set(state.videos.map(\.id))
        let additions = videos.filter { !existing.contains($0.id) }

        state.videos.append(contentsOf: additions)
        state.page = page
        state.isLoading = false
        // Sites keep serving pages after they run out of new videos, so stop
        // paging when a page adds nothing.
        state.hasMore = !videos.isEmpty && !additions.isEmpty
        feeds[feed.id] = state
    }

    private func merge(_ videos: [Video], page: Int) {
        let existing = Set(search.videos.map(\.id))
        let additions = videos.filter { !existing.contains($0.id) }

        search.videos.append(contentsOf: additions)
        search.page = page
        search.isLoading = false
        search.hasMore = !videos.isEmpty && !additions.isEmpty
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
