/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A content source for mat6tube.com.
*/

import Foundation

/// A content source for mat6tube.com.
///
/// The site doesn't publish an API, so this source requests the same pages a
/// browser requests and reads the metadata out of the markup. A redesign there
/// breaks parsing, and this file is the only place that needs fixing.
struct Mat6TubeSource: ContentSource {
    let id = "mat6tube"
    let displayName = "mat6tube"
    let homeURL = URL(string: "https://mat6tube.com/")!

    var feeds: [Feed] {
        [
            makeFeed("popular",
                     name: String(localized: "Popular", comment: "Collection name"),
                     description: String(localized: "The videos everyone is watching right now, ranked by view count.",
                                         comment: "The description of a collection of videos."),
                     icon: "flame"),
            makeFeed("recent",
                     name: String(localized: "Just Added", comment: "Collection name"),
                     description: String(localized: "The newest uploads, in the order they arrived.",
                                         comment: "The description of a collection of videos."),
                     icon: "sparkles"),
            makeFeed("explore",
                     name: String(localized: "Explore", comment: "Collection name"),
                     description: String(localized: "A wider mix, pulled from across the catalog.",
                                         comment: "The description of a collection of videos."),
                     icon: "shuffle"),
            makeFeed("now",
                     name: String(localized: "Watching Now", comment: "Collection name"),
                     description: String(localized: "What other people have open at this moment.",
                                         comment: "The description of a collection of videos."),
                     icon: "eye"),
            makeFeed("day",
                     name: String(localized: "Top Today", comment: "Collection name"),
                     description: String(localized: "The most-watched videos of the last twenty-four hours.",
                                         comment: "The description of a collection of videos."),
                     icon: "sun.max",
                     group: .chart),
            makeFeed("week",
                     name: String(localized: "Top This Week", comment: "Collection name"),
                     description: String(localized: "The most-watched videos of the past seven days.",
                                         comment: "The description of a collection of videos."),
                     icon: "calendar",
                     group: .chart),
            makeFeed("month",
                     name: String(localized: "Top This Month", comment: "Collection name"),
                     description: String(localized: "The most-watched videos of the past month.",
                                         comment: "The description of a collection of videos."),
                     icon: "calendar.badge.clock",
                     group: .chart)
        ]
    }

    // MARK: - URLs

    func listingURL(for feed: Feed, page: Int) -> URL? {
        guard feed.sourceID == id else { return nil }

        // Two listings have their own paths; the rest are ranges of /recent.
        //
        // Popular needs the `/trending` segment — `/popular` alone is a 404 that
        // still renders a listing, so it looks like it works until the ranking is
        // compared. Leaving the range off /recent doesn't work either: the site
        // ignores an unrecognized or absent range and serves the monthly chart, so
        // Popular and Top This Month were the same 24 videos.
        let path: String
        switch feed.slug {
        case "now": path = "now"
        case "popular": path = "popular/trending"
        default: path = "recent"
        }
        var components = URLComponents(url: homeURL.appending(path: path), resolvingAgainstBaseURL: false)!

        var items = [URLQueryItem]()
        if path == "recent" {
            items.append(URLQueryItem(name: "range", value: feed.slug))
        }
        if page > 1 {
            items.append(URLQueryItem(name: "p", value: String(page)))
        }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }

    func searchURL(query: String, page: Int) -> URL? {
        // The site encodes a search as a path component, with `+` between words.
        let terms = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: "+")
        guard !terms.isEmpty else { return nil }

        var components = URLComponents(url: homeURL.appending(path: "video/\(terms)"), resolvingAgainstBaseURL: false)!
        if page > 1 {
            components.queryItems = [URLQueryItem(name: "p", value: String(page))]
        }
        return components.url
    }

    func watchURL(forItem itemID: String) -> URL {
        homeURL.appending(path: "watch/\(itemID)")
    }

    /// The site's identifiers are bare path components, but its links sometimes
    /// carry a tracking query. Keep only the component itself.
    func normalizedItemID(_ itemID: String) -> String {
        itemID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { $0 != "?" && $0 != "#" }
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - Parsing

    func videos(inListing response: SourceResponse) throws -> [Video] {
        videos(inListing: response.text)
    }

    func details(inWatchPage response: SourceResponse, itemID: String) throws -> VideoDetails {
        let html = response.text
        return VideoDetails(
            sources: streams(inWatchPage: html),
            related: videos(inListing: html).filter { $0.itemID != itemID },
            video: video(inWatchPage: html, itemID: itemID)
        )
    }

    private func videos(inListing html: String) -> [Video] {
        // Each card begins with an `item` container. Splitting on it keeps every
        // field with the card it belongs to.
        let cards = html.components(separatedBy: "<div class=\"item\">").dropFirst()
        var seen = Set<String>()
        return cards.compactMap(video(inCard:)).filter { seen.insert($0.itemID).inserted }
    }

    private func video(inCard card: String) -> Video? {
        guard let itemID = HTMLScanner.firstMatch(of: #"href="/watch/([^"]+)""#, in: card) else { return nil }

        // Listing pages defer the poster to `data-src`; related-video cards use `src`.
        let thumbnail = HTMLScanner.firstMatch(of: #"data-src="(https?://[^"]+)""#, in: card)
            ?? HTMLScanner.firstMatch(of: #"<img[^>]+src="(https?://[^"]+)""#, in: card)

        let title = HTMLScanner.firstMatch(of: #"class="title">([^<]*)<"#, in: card) ?? ""
        let alternateTitle = HTMLScanner.firstMatch(of: #"<img[^>]+alt="([^"]*)""#, in: card) ?? ""
        let clock = HTMLScanner.firstMatch(of: #"class="m_time">.*?</svg>\s*([^<]+)<"#, in: card) ?? ""
        let views = HTMLScanner.firstMatch(of: #"class="m_views">.*?</svg>\s*([^<]+)<"#, in: card) ?? ""

        return Video(
            sourceID: id,
            itemID: HTMLScanner.decode(itemID),
            rawTitle: HTMLScanner.decode(title.isEmpty ? alternateTitle : title),
            thumbnailURL: thumbnail.flatMap { URL(string: HTMLScanner.decode($0)) },
            previewURL: HTMLScanner.firstMatch(of: #"data-trailer_url="([^"]+)""#, in: card)
                .flatMap { URL(string: HTMLScanner.decode($0)) },
            duration: HTMLScanner.seconds(fromClock: clock),
            views: views.trimmingCharacters(in: .whitespacesAndNewlines),
            isHD: card.contains("hd_mark")
        )
    }

    private func streams(inWatchPage html: String) -> [StreamSource] {
        // The page hands its player a JSON playlist of signed media URLs.
        guard let json = HTMLScanner.firstMatch(of: #"window\.playlist\s*=\s*(\{.*?\});"#,
                                                in: html,
                                                dotMatchesNewlines: true),
              let data = json.data(using: .utf8),
              let playlist = try? JSONDecoder().decode(Playlist.self, from: data) else {
            return []
        }
        return playlist.sources
            .compactMap { source in
                guard let url = URL(string: source.file) else { return nil }
                return StreamSource(url: url, height: Int(source.label ?? "") ?? 0)
            }
            .sorted { $0.height > $1.height }
    }

    private func video(inWatchPage html: String, itemID: String) -> Video? {
        guard let title = HTMLScanner.metaContent("og:title", in: html) else { return nil }

        let keywords = (HTMLScanner.metaContent("keywords", in: html) ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let uploaded = HTMLScanner.metaContent("ya:ovs:upload_date", in: html)
        let duration = HTMLScanner.firstMatch(of: #""duration":\s*"([^"]+)""#, in: html) ?? ""

        return Video(
            sourceID: id,
            itemID: itemID,
            rawTitle: title,
            thumbnailURL: HTMLScanner.metaContent("og:image", in: html).flatMap { URL(string: $0) },
            duration: HTMLScanner.seconds(fromISO8601: duration),
            views: HTMLScanner.abbreviated(HTMLScanner.metaContent("ya:ovs:views_total", in: html)),
            isHD: HTMLScanner.metaContent("ya:ovs:quality", in: html) == "HD",
            tags: Array(keywords.prefix(12)),
            uploadDate: uploaded.flatMap { Date.siteFormatter.date(from: $0) }
        )
    }

    /// The shape of the JSON playlist that the watch page declares for its player.
    private struct Playlist: Decodable {
        struct Source: Decodable {
            var file: String
            var label: String?
        }
        var sources: [Source]
    }
}
