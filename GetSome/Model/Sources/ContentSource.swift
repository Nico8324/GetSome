/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The interface that every site the app can browse conforms to.
*/

import Foundation

/// A group that determines where a feed appears in the app's navigation.
enum FeedGroup: String, Sendable, Hashable, CaseIterable {
    /// A feed people browse by topic or freshness.
    case collection
    /// A feed that ranks videos over a time window.
    case chart
    /// A feed for one of a site's own categories, discovered at runtime.
    ///
    /// Unlike the others these aren't declared in code — a site can publish
    /// thousands — so they never appear as sidebar tabs. See ``navigableGroups``.
    case category

    /// The groups that get their own section in the sidebar.
    static let navigableGroups: [FeedGroup] = [.collection, .chart]
}

/// A listing that several sites publish their own version of.
///
/// Sites name the same idea differently — one calls its front page "Popular" and
/// another calls it "Hot" — so a source tags its feed with the kind it is rather
/// than the word it uses. Feeds sharing a kind are presented as one cross-site
/// collection; see ``ContentSources/mergedFeeds``.
/// Every listing the app presents is one of these, and a listing only one site
/// publishes is a kind with one member rather than a card that names a site.
enum FeedKind: String, Sendable, Hashable, CaseIterable {
    case popular
    case latest
    case watchingNow
    case explore
    case verified
    case newReleases
    case uncensored
    case englishSubtitles
    case chineseSubtitles
    case liked
    case topDay
    case topWeek
    case topMonth
    case topRated

    /// The name of the merged collection, in presentation order.
    var name: String {
        switch self {
        case .popular: String(localized: "Popular", comment: "Collection name")
        case .latest: String(localized: "Just Added", comment: "Collection name")
        case .watchingNow: String(localized: "Watching Now", comment: "Collection name")
        case .explore: String(localized: "Explore", comment: "Collection name")
        case .verified: String(localized: "Verified", comment: "Collection name")
        case .newReleases: String(localized: "New Releases", comment: "Collection name")
        case .uncensored: String(localized: "Uncensored", comment: "Collection name")
        case .englishSubtitles: String(localized: "English Subtitles", comment: "Collection name")
        case .chineseSubtitles: String(localized: "Chinese Subtitles", comment: "Collection name")
        case .liked: String(localized: "Liked", comment: "Collection name")
        case .topDay: String(localized: "Top Today", comment: "Collection name")
        case .topWeek: String(localized: "Top This Week", comment: "Collection name")
        case .topMonth: String(localized: "Top This Month", comment: "Collection name")
        case .topRated: String(localized: "Top Rated", comment: "Collection name")
        }
    }

    /// What the collection contains when it genuinely spans several sites.
    ///
    /// Nil for the kinds only one site publishes today: saying "across every site"
    /// about a listing MissAV alone offers would be a claim the shelf doesn't meet.
    /// Those fall back to the site's own wording — see ``ContentSources/mergedFeeds``.
    var crossSiteDescription: String? {
        switch self {
        case .popular:
            String(localized: "What's being watched right now, across every site.",
                   comment: "The description of a collection of videos.")
        case .latest:
            String(localized: "The newest uploads from every site, side by side.",
                   comment: "The description of a collection of videos.")
        case .topDay:
            String(localized: "The day's most-watched videos, across every site.",
                   comment: "The description of a collection of videos.")
        case .topWeek:
            String(localized: "The week's most-watched videos, across every site.",
                   comment: "The description of a collection of videos.")
        case .topMonth:
            String(localized: "The month's most-watched videos, across every site.",
                   comment: "The description of a collection of videos.")
        case .topRated:
            String(localized: "The best-rated videos, across every site.",
                   comment: "The description of a collection of videos.")
        case .watchingNow, .explore, .verified, .newReleases,
             .uncensored, .englishSubtitles, .chineseSubtitles, .liked:
            nil
        }
    }

    var icon: String {
        switch self {
        case .popular: "flame"
        case .latest: "sparkles"
        case .watchingNow: "eye"
        case .explore: "shuffle"
        case .verified: "checkmark.seal"
        case .newReleases: "calendar.badge.plus"
        case .uncensored: "eye.slash"
        case .englishSubtitles: "captions.bubble"
        case .chineseSubtitles: "character.bubble"
        case .liked: "heart"
        case .topDay: "sun.max"
        case .topWeek: "calendar"
        case .topMonth: "calendar.badge.clock"
        case .topRated: "star"
        }
    }

    var group: FeedGroup {
        switch self {
        case .popular, .latest, .watchingNow, .explore, .verified,
             .newReleases, .uncensored, .englishSubtitles, .chineseSubtitles, .liked:
            .collection
        case .topDay, .topWeek, .topMonth, .topRated:
            .chart
        }
    }
}

/// A single listing a source publishes, such as "most popular" or "added today".
///
/// A feed belongs to exactly one source. Its ``slug`` is whatever that source
/// needs to build a URL for it, so no other type has to know the site's routing.
/// The exception is a merged feed, whose ``sourceID`` is ``ContentSources/allSitesID``
/// and which stands for every site's version of one ``FeedKind`` at once.
struct Feed: Identifiable, Hashable, Sendable {
    /// The identifier of the source that publishes this feed.
    let sourceID: String
    /// The source's own name for the listing, which it maps back to a URL.
    let slug: String
    let name: String
    let description: String
    /// An SF Symbol name.
    let icon: String
    let group: FeedGroup
    /// The cross-site listing this one is a version of, when it is one.
    let kind: FeedKind?

    var id: String { "\(sourceID)/\(slug)" }

    init(
        sourceID: String,
        slug: String,
        name: String,
        description: String,
        icon: String,
        group: FeedGroup = .collection,
        kind: FeedKind? = nil
    ) {
        self.sourceID = sourceID
        self.slug = slug
        self.name = name
        self.description = description
        self.icon = icon
        self.group = group
        self.kind = kind
    }
}

/// The bytes a source's endpoint returned, ready to parse.
///
/// Sources receive the raw data rather than a string so a future source can serve
/// JSON just as easily as markup.
struct SourceResponse: Sendable {
    let url: URL
    let data: Data

    /// The response decoded as text.
    ///
    /// Most sites serve UTF-8. This falls back to Latin-1 rather than losing a page
    /// to one malformed byte.
    var text: String {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }
}

/// A single playback source for a video.
struct StreamSource: Sendable, Hashable {
    /// The media URL. Sites commonly sign these, so they expire after a while.
    var url: URL
    /// The vertical resolution, such as `720`. Zero when the source doesn't publish one.
    var height: Int
}

/// The playback sources and metadata that a source publishes for a single video.
struct VideoDetails: Sendable {
    /// The playback sources, ordered from highest to lowest resolution.
    var sources: [StreamSource] = []
    /// Videos the site suggests alongside this one.
    var related: [Video] = []
    /// Metadata the detail page publishes that a listing page doesn't.
    var video: Video?
    /// The uploader's display name, when the source can identify them.
    var uploaderName: String?
    /// A feed of videos from the uploader, when available.
    var uploaderFeed: Feed?
    /// Scene preview thumbnails for timeline scrubbing, when available.
    var sceneThumbnailURLs: [URL] = []
}

/// A site the app can browse.
///
/// Adding a site means writing one conformance: describe its feeds, build its URLs,
/// and turn its responses into ``Video`` values. Nothing above this layer — the
/// client, the store, or any view — needs to change.
protocol ContentSource: Sendable {
    /// A stable slug that identifies this source in saved data and video identifiers.
    ///
    /// Prefer a name for the service rather than its domain, since domains move.
    /// If you ever do have to change it, list the old value in ``previousIDs``
    /// rather than orphaning everything people saved under it.
    var id: String { get }

    /// Identifiers this source used to go by.
    ///
    /// The registry resolves these to this source, so saved videos and in-flight
    /// requests survive a rename.
    var previousIDs: [String] { get }

    /// The name to show people.
    var displayName: String { get }

    /// The site's home page.
    var homeURL: URL { get }

    /// The listings this source publishes, in the order to present them.
    var feeds: [Feed] { get }

    /// A Boolean value that indicates whether this source can search its catalog.
    var supportsSearch: Bool { get }

    /// The feed to lead with on the Watch Now screen.
    var featuredFeed: Feed { get }

    /// The feed of newest videos, shown beneath the featured row.
    var latestFeed: Feed { get }

    /// Returns a request the site responds to, including whatever headers it expects.
    func request(for url: URL) -> URLRequest

    /// Returns the URL of a page of videos in the specified feed.
    /// - Parameters:
    ///   - feed: One of this source's own feeds.
    ///   - page: A one-based page number.
    /// - Returns: `nil` when the feed doesn't page that far, or isn't this source's.
    func listingURL(for feed: Feed, page: Int) -> URL?

    /// Returns the URL of a page of search results, or `nil` when the source can't search.
    func searchURL(query: String, page: Int) -> URL?

    /// Returns the URL of the page that lists this source's categories.
    ///
    /// Returns `nil` for a site that publishes no category index — mat6tube, for
    /// one — in which case the app simply offers none for it.
    func categoriesURL() -> URL?

    /// Returns the categories a source's index page contains.
    ///
    /// Categories come back as ``Feed`` values in the ``FeedGroup/category`` group,
    /// so everything downstream — the store, the feed screen, paging — treats them
    /// exactly like a declared feed.
    func categories(in response: SourceResponse) throws -> [Feed]

    /// Returns the URL of the page that presents a single video.
    func watchURL(forItem itemID: String) -> URL

    /// Reduces a site's identifier to one canonical form.
    ///
    /// Sites hand out the same video under variants — a trailing slash, a tracking
    /// parameter, a different case. Normalizing here keeps one video from being
    /// saved twice under two identities.
    func normalizedItemID(_ itemID: String) -> String

    /// Returns the videos a listing or search response contains.
    func videos(inListing response: SourceResponse) throws -> [Video]

    /// Returns the item identifiers a listing publishes when it carries ids alone.
    ///
    /// Most listings publish whole videos. A few publish only identifiers — xvideos'
    /// liked-videos list is one — and each has to be resolved before it can be drawn.
    func itemIDs(inListing response: SourceResponse) throws -> [String]

    /// Returns the playback sources and metadata a detail response contains.
    func details(inWatchPage response: SourceResponse, itemID: String) throws -> VideoDetails

    /// A second request needed before playback, for sites that don't put their
    /// media URLs on the watch page.
    ///
    /// Return `nil` when the watch page already carries everything. xvideos, for
    /// one, publishes only a low rendition inline and serves the rest from an RPC
    /// its own player calls.
    func streamsURL(forItem itemID: String) -> URL?

    /// Parses the response from ``streamsURL(forItem:)`` into playback sources.
    func streams(in response: SourceResponse) throws -> [StreamSource]

    /// Chooses which resolution to play from the ones the source published.
    func preferredStream(from streams: [StreamSource]) -> StreamSource?

    /// Whether a feed can only be read while signed in.
    func requiresSignIn(_ feed: Feed) -> Bool

    /// The request that loads a page of a feed.
    ///
    /// Defaults to a GET of ``listingURL(for:page:)``. A source overrides this when a
    /// listing isn't a page at all — xvideos serves its account data from a JSON API
    /// that only answers POST.
    func listingRequest(for feed: Feed, page: Int) -> URLRequest?

    /// The headers to attach to media requests for this source.
    ///
    /// The player fetches manifests and segments on its own networking stack, which
    /// sends none of what ``request(for:)`` sets. At least one media CDN answers 403
    /// without a referer, so without these a stream resolves and then refuses to
    /// play — see ``PlayerModel``.
    func playbackHeaders(for url: URL) -> [String: String]
}

// MARK: - Defaults

extension ContentSource {
    var supportsSearch: Bool { true }

    var previousIDs: [String] { [] }

    /// Trims whitespace and the slashes a path component may carry.
    func normalizedItemID(_ itemID: String) -> String {
        itemID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var featuredFeed: Feed {
        feeds.first { $0.group == .collection } ?? feeds[0]
    }

    var latestFeed: Feed {
        feeds.dropFirst().first { $0.group == .collection } ?? featuredFeed
    }

    /// A request that identifies itself as a browser.
    ///
    /// Most tube sites serve a reduced page — or nothing — to clients they don't
    /// recognize, so this is the sensible default for a new source.
    func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(homeURL.absoluteString, forHTTPHeaderField: "Referer")
        return request
    }

    func searchURL(query: String, page: Int) -> URL? { nil }

    func categoriesURL() -> URL? { nil }

    func streamsURL(forItem itemID: String) -> URL? { nil }

    func streams(in response: SourceResponse) throws -> [StreamSource] { [] }

    func categories(in response: SourceResponse) throws -> [Feed] { [] }

    /// Whether a feed can only be read while signed in.
    ///
    /// Default false: most feeds are public, and a source without accounts never
    /// answers anything else.
    func requiresSignIn(_ feed: Feed) -> Bool { false }

    /// Most listings publish whole videos, so there are no bare ids to resolve.
    func itemIDs(inListing response: SourceResponse) throws -> [String] { [] }

    func listingRequest(for feed: Feed, page: Int) -> URLRequest? {
        listingURL(for: feed, page: page).map { request(for: $0) }
    }

    /// Sends media requests with the same identification a page request carries.
    ///
    /// A site that gates its pages usually gates its media the same way, so reusing
    /// ``request(for:)`` keeps that knowledge in one place per source rather than
    /// splitting it between browsing and playback.
    func playbackHeaders(for url: URL) -> [String: String] {
        request(for: url).allHTTPHeaderFields ?? [:]
    }

    /// A Boolean value that indicates whether this source publishes categories.
    var hasCategories: Bool { categoriesURL() != nil }

    /// Prefers the tallest stream that fits the quality a person chose.
    ///
    /// Sources that publish no resolution for a stream are used as a last resort,
    /// since there's no way to tell whether they fit.
    func preferredStream(from streams: [StreamSource]) -> StreamSource? {
        let ceiling = PlaybackSettings.maximumQuality.ceiling
        let ordered = streams.sorted { $0.height > $1.height }
        let known = ordered.filter { $0.height > 0 }
        if let best = known.first(where: { $0.height <= ceiling }) { return best }
        // Everything on offer is taller than requested, so take the smallest.
        return known.last ?? ordered.first
    }

    /// A Safari user agent string.
    static var browserUserAgent: String {
        """
        Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) \
        Version/17.0 Safari/605.1.15
        """
    }

    /// Builds one of this source's feeds.
    func makeFeed(
        _ slug: String,
        name: String,
        description: String,
        icon: String,
        group: FeedGroup = .collection,
        kind: FeedKind? = nil
    ) -> Feed {
        Feed(sourceID: id, slug: slug, name: name, description: description,
             icon: icon, group: group, kind: kind)
    }

    /// Returns this source's feed with the specified slug.
    func feed(withSlug slug: String) -> Feed? {
        feeds.first { $0.slug == slug }
    }
}

/// The failures that loading content can produce.
enum ContentError: LocalizedError {
    case unknownSource(String)
    case unsupportedFeed(String)
    case searchUnavailable(String)
    case badResponse(Int)
    case unreadablePage
    case noResults(String)
    case noPlayableSource
    case redirectedHome(String)

    var errorDescription: String? {
        switch self {
        case .unknownSource(let id):
            String(localized: "There’s no site named “\(id)” in this app.", comment: "An error message")
        case .unsupportedFeed(let name):
            String(localized: "“\(name)” isn’t available on this site.", comment: "An error message")
        case .searchUnavailable(let name):
            String(localized: "\(name) doesn’t support search.", comment: "An error message")
        case .badResponse(let status):
            String(localized: "The site returned an error (\(status)).", comment: "A network error message")
        case .unreadablePage:
            String(localized: "The site returned a page this app can’t read.", comment: "A parsing error message")
        case .noResults(let name):
            String(localized: """
                \(name) answered, but this app didn’t recognize anything on the page. \
                The site has probably changed. Profile › Diagnostics can export what it sent.
                """, comment: "An error shown when a site's markup no longer parses")
        case .noPlayableSource:
            String(localized: "This video doesn’t have a stream to play.", comment: "A playback error message")
        case .redirectedHome(let name):
            String(localized: """
                \(name) sent this request to its home page instead of the feed. That usually \
                means the site doesn’t serve this content where you are.
                """, comment: "An error shown when a site redirects every request to its home page")
        }
    }
}
