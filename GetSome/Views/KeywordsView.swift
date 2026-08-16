/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that gathers every keyword the app has seen into one browsable list.
*/

import SwiftUI
import SwiftData

/// A view that gathers every keyword the app has seen into one browsable list.
///
/// The sites publish keywords per video and nothing else — there's no vocabulary to
/// download, no counts, no index. So this builds one from what's already loaded:
/// every video in every feed the app has fetched this session, plus everything
/// saved. That makes the list a record of the catalog as browsed rather than the
/// catalog entire, which is the honest version and costs no requests.
///
/// Keywords are counted case-insensitively but shown as the sites write them, and
/// tapping one searches every site. See ``ContentClient/videos(matchingEverywhere:page:)``.
struct KeywordsView: View {
    @Environment(FeedStore.self) private var feeds

    @Query(sort: \SavedVideo.createdAt, order: .reverse)
    private var saved: [SavedVideo]

    @State private var query = ""

    let namespace: Namespace.ID

    /// One entry per keyword, most-seen first.
    private struct Keyword: Identifiable {
        /// The lowercased form, which is what counting is done on.
        let id: String
        /// The spelling to show, taken from the first video that used it.
        let name: String
        let count: Int
        /// The sites that publish this keyword, for the subtitle.
        let sourceIDs: Set<String>
    }

    private var keywords: [Keyword] {
        var names = [String: String]()
        var counts = [String: Int]()
        var sites = [String: Set<String>]()

        // Saved videos first so their spelling wins: they're the ones a person
        // chose, and the same keyword can arrive capitalized differently per site.
        let videos = saved.map(\.video) + feeds.allLoadedVideos
        for video in videos {
            for keyword in video.keywords {
                let key = keyword.lowercased()
                if names[key] == nil { names[key] = keyword }
                counts[key, default: 0] += 1
                sites[key, default: []].insert(video.sourceID)
            }
        }

        return counts
            .map { Keyword(id: $0.key, name: names[$0.key] ?? $0.key,
                           count: $0.value, sourceIDs: sites[$0.key] ?? []) }
            .sorted { first, second in
                first.count == second.count
                    ? first.name.localizedCompare(second.name) == .orderedAscending
                    : first.count > second.count
            }
    }

    private var filtered: [Keyword] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return keywords }
        return keywords.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        List(filtered) { keyword in
            NavigationLink(value: NavigationNode.tag(sourceID: FeedStore.allSitesID,
                                                     keyword: keyword.name)) {
                LabeledContent {
                    Text(keyword.count, format: .number)
                        .foregroundStyle(.secondary)
                        .font(.footnote.monospacedDigit())
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(keyword.name)
                        if ContentSources.hasMultipleSources {
                            Text(siteLine(for: keyword))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Keywords")
        #if !os(tvOS)
        .searchable(text: $query, prompt: Text("Filter keywords"))
        #endif
        .overlay {
            if keywords.isEmpty {
                ContentUnavailableView(
                    "No keywords yet",
                    systemImage: "number",
                    description: Text("Keywords appear here as videos carrying them load.")
                )
            } else if filtered.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func siteLine(for keyword: Keyword) -> String {
        keyword.sourceIDs
            .compactMap { ContentSources.source(with: $0)?.displayName }
            .sorted()
            .formatted(.list(type: .and))
    }
}
