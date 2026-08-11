/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A single unit in the app's navigation stack.
*/

import SwiftUI

/// A single unit in the app's navigation stack.
enum NavigationNode: Equatable, Hashable, Identifiable {
    /// A feed, identified by ``Feed/id`` so the node stays valid across sources.
    case feed(Feed.ID)
    /// A video, identified by ``Video/id``.
    case video(VideoID)
    /// A keyword search on a particular source.
    case tag(sourceID: String, keyword: String)
    /// The list of categories a particular source publishes.
    case categories(sourceID: String)

    var id: String {
        switch self {
        case .feed(let id): "feed-\(id)"
        case .video(let id): "video-\(id.description)"
        case .tag(let sourceID, let keyword): "tag-\(sourceID)-\(keyword)"
        case .categories(let sourceID): "categories-\(sourceID)"
        }
    }
}
