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
    /// Removing a source is the same one-line change. Anything saved from it keeps
    /// working as a record — see ``Video/isAvailable`` — rather than disappearing.
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

    /// The sites the app browses, named for the age gate.
    ///
    /// Built from the registry so adding a source can't leave the gate naming an
    /// out-of-date list — it claimed a single site well after there were four.
    static var displayNameList: String {
        all.map(\.displayName).formatted(.list(type: .and))
    }

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

    /// The identifier a feed carries when it stands for every site at once.
    static let allSitesID = "all"

    /// Every feed of every source.
    static var allFeeds: [Feed] {
        all.flatMap(\.feeds)
    }

    /// The feeds that make up a merged feed, in registry order.
    ///
    /// The site a person chose to open with comes first, so it leads the interleave
    /// and the merged collection's cover art is the one they'd expect.
    static func members(of merged: Feed) -> [Feed] {
        guard let kind = merged.kind, merged.isMerged else { return [] }
        let primaryID = primary.id
        return allFeeds
            .filter { $0.kind == kind && !$0.isMerged }
            .sorted { first, second in
                (first.sourceID == primaryID ? 0 : 1) < (second.sourceID == primaryID ? 0 : 1)
            }
    }

    /// One feed per listing the app knows about, each drawing from whichever sites
    /// publish it.
    ///
    /// Sites overlap heavily at the top — nearly all have a front page and a
    /// newest-first list — so presenting each site's version separately filled the
    /// shelves with four cards meaning the same thing. Every listing becomes one
    /// card here; see ``ContentClient/videos(for:page:)`` for how a page is
    /// gathered.
    ///
    /// A listing only one site publishes is merged too, with one member. That isn't
    /// a special case worth writing: the card is named for what it contains rather
    /// than for who publishes it either way, and the day a second site adds the same
    /// listing it fills in with no further change. Which sites actually back a given
    /// card is answered by ``Feed/sourceCredit`` on the feed's own screen.
    static var mergedFeeds: [Feed] {
        let feeds = allFeeds
        return FeedKind.allCases.compactMap { kind in
            let members = feeds.filter { $0.kind == kind }
            guard let first = members.first else { return nil }
            let spansSites = Set(members.map(\.sourceID)).count > 1
            let description = (spansSites ? kind.crossSiteDescription : nil) ?? first.description
            return Feed(sourceID: allSitesID, slug: kind.rawValue, name: kind.name,
                        description: description, icon: kind.icon,
                        group: kind.group, kind: kind)
        }
    }

    /// The feeds the app puts on its shelves for the specified group.
    ///
    /// Merged only. Listing each site's version separately filled the shelves with
    /// four cards that meant the same thing, and a person browsing shouldn't have to
    /// pick a site before they can pick a mood. What one site publishes alone — its
    /// own specialties, like MissAV's subtitled listings — is still browsable a site
    /// at a time in ``BrowseView``, which is the screen for that question.
    ///
    /// Falls back to the single site's own feeds when there's nothing to merge.
    static func feeds(in group: FeedGroup) -> [Feed] {
        let merged = mergedFeeds.filter { $0.group == group }
        guard merged.isEmpty else { return merged }
        return allFeeds.filter { $0.group == group }
    }

    /// Returns the feed with the specified identifier.
    static func feed(with id: Feed.ID) -> Feed? {
        allFeeds.first { $0.id == id } ?? mergedFeeds.first { $0.id == id }
    }
}

extension Feed {
    /// A Boolean value that indicates whether this feed draws from every site at once.
    var isMerged: Bool { sourceID == ContentSources.allSitesID }

    /// The name of the source that publishes this feed.
    var sourceName: String {
        ContentSources.source(with: sourceID)?.displayName ?? sourceID
    }

    /// The feed's name, qualified by its source when the app browses more than one.
    ///
    /// A merged feed names no site, because it is all of them.
    var qualifiedName: String {
        guard !isMerged, ContentSources.hasMultipleSources else { return name }
        return "\(sourceName) · \(name)"
    }

    /// The line that credits where a feed's videos come from.
    ///
    /// A merged feed names every site it draws from: a shelf mixing four catalogs
    /// should say so, or the mix reads as one site with strangely varied artwork.
    var sourceCredit: String {
        guard isMerged else { return sourceName }
        let names = ContentSources.members(of: self)
            .map(\.sourceName)
            .sorted()
        return names.formatted(.list(type: .and))
    }
}
