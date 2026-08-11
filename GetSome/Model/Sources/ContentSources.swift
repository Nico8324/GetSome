/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The registry of sites the app can browse.
*/

import Foundation

/// The registry of sites the app can browse.
///
/// Adding a site is a one-line change here plus its ``ContentSource`` conformance.
enum ContentSources {
    /// Every source the app ships with, in presentation order.
    static let all: [any ContentSource] = [
        Mat6TubeSource(),
        PornhubSource(),
        XVideosSource(),
        MissAVSource()
    ]

    /// The user defaults key that holds the site a person chose to open with.
    static let primarySourceKey = "primarySourceID"

    /// The source the app opens with.
    ///
    /// This follows the site chosen on the profile screen, falling back to the
    /// first registered source when that choice is missing or no longer shipped.
    static var primary: any ContentSource {
        if let id = UserDefaults.standard.string(forKey: primarySourceKey),
           let chosen = source(with: id) {
            return chosen
        }
        return all[0]
    }

    /// A Boolean value that indicates whether the interface needs to name its sources.
    static var hasMultipleSources: Bool { all.count > 1 }

    /// Returns the source with the specified identifier.
    ///
    /// This also resolves identifiers a source used to go by, so a rename doesn't
    /// strand videos people saved under the old name.
    static func source(with id: String) -> (any ContentSource)? {
        all.first { $0.id == id } ?? all.first { $0.previousIDs.contains(id) }
    }

    /// Returns the source that publishes the specified feed.
    static func source(of feed: Feed) -> (any ContentSource)? {
        source(with: feed.sourceID)
    }

    /// Every feed of every source.
    static var allFeeds: [Feed] {
        all.flatMap(\.feeds)
    }

    /// Every feed of every source in the specified group.
    static func feeds(in group: FeedGroup) -> [Feed] {
        allFeeds.filter { $0.group == group }
    }

    /// Returns the feed with the specified identifier.
    static func feed(with id: Feed.ID) -> Feed? {
        allFeeds.first { $0.id == id }
    }
}

extension Feed {
    /// The name of the source that publishes this feed.
    var sourceName: String {
        ContentSources.source(with: sourceID)?.displayName ?? sourceID
    }

    /// The feed's name, qualified by its source when the app browses more than one.
    var qualifiedName: String {
        ContentSources.hasMultipleSources ? "\(sourceName) · \(name)" : name
    }
}
