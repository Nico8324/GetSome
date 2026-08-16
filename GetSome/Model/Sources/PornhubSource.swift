/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A content source for pornhub.com.
*/

import Foundation

/// A content source for pornhub.com.
///
/// Listings are server-rendered, so they're read the same way as any other page.
/// The watch page is different: it hands its player a `flashvars_<id>` JSON blob
/// containing signed HLS manifests, which is where playback comes from.
struct PornhubSource: ContentSource {
    let id = "pornhub"
    let displayName = "Pornhub"
    let homeURL = URL(string: "https://www.pornhub.com/")!

    var feeds: [Feed] {
        [
            makeFeed("hot",
                     name: String(localized: "Hot", comment: "Collection name"),
                     description: String(localized: "What's hot right now.",
                                         comment: "The description of a collection of videos."),
                     icon: "flame",
                     kind: .popular),
            makeFeed("new",
                     name: String(localized: "Just Added", comment: "Collection name"),
                     description: String(localized: "The newest uploads, in the order they arrived.",
                                         comment: "The description of a collection of videos."),
                     icon: "sparkles",
                     kind: .latest),
            makeFeed("top",
                     name: String(localized: "Top Rated", comment: "Collection name"),
                     description: String(localized: "The best rated videos on the site.",
                                         comment: "The description of a collection of videos."),
                     icon: "star",
                     group: .chart,
                     kind: .topRated),
            makeFeed("week",
                     name: String(localized: "Most Viewed This Week", comment: "Collection name"),
                     description: String(localized: "The most-watched videos of the past seven days.",
                                         comment: "The description of a collection of videos."),
                     icon: "calendar",
                     group: .chart,
                     kind: .topWeek),
            makeFeed("month",
                     name: String(localized: "Most Viewed This Month", comment: "Collection name"),
                     description: String(localized: "The most-watched videos of the past month.",
                                         comment: "The description of a collection of videos."),
                     icon: "calendar.badge.clock",
                     group: .chart,
                     kind: .topMonth)
        ]
    }

    /// Adds the cookies the site's own age gate sets.
    ///
    /// Without them every listing comes back flagged `Safe for work` — podcasts,
    /// interviews and promos instead of the actual catalog. The app has already
    /// asked for age confirmation before any of this runs; see `AgeGateView`.
    func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(homeURL.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(Self.ageCookies, forHTTPHeaderField: "Cookie")
        return request
    }

    private static let ageCookies = [
        "accessAgeDisclaimerPH=1",
        "accessAgeDisclaimerUK=1",
        "accessPH=1",
        "age_verified=1",
        "cookiesBannerSeen=1",
        "platform=pc"
    ].joined(separator: "; ")

    // MARK: - URLs

    func listingURL(for feed: Feed, page: Int) -> URL? {
        guard feed.sourceID == id else { return nil }

        // The site selects a listing with `o`, and narrows a chart with `t`.
        var items: [URLQueryItem]
        switch feed.slug {
        case "hot": items = [URLQueryItem(name: "o", value: "ht")]
        case "new": items = [URLQueryItem(name: "o", value: "mr")]
        case "top": items = [URLQueryItem(name: "o", value: "tr")]
        case "week": items = [URLQueryItem(name: "o", value: "mv"), URLQueryItem(name: "t", value: "w")]
        case "month": items = [URLQueryItem(name: "o", value: "mv"), URLQueryItem(name: "t", value: "m")]
        default: return nil
        }
        if page > 1 {
            items.append(URLQueryItem(name: "page", value: String(page)))
        }

        var components = URLComponents(url: homeURL.appending(path: "video"), resolvingAgainstBaseURL: false)!
        components.queryItems = items
        return components.url
    }

    func searchURL(query: String, page: Int) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components = URLComponents(url: homeURL.appending(path: "video/search"),
                                       resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "search", value: trimmed)]
        if page > 1 {
            items.append(URLQueryItem(name: "page", value: String(page)))
        }
        components.queryItems = items
        return components.url
    }

    func watchURL(forItem itemID: String) -> URL {
        var components = URLComponents(url: homeURL.appending(path: "view_video.php"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "viewkey", value: itemID)]
        return components.url ?? homeURL
    }

    /// View keys are bare alphanumerics; drop anything a link appends to one.
    func normalizedItemID(_ itemID: String) -> String {
        itemID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { $0 != "?" && $0 != "#" && $0 != "&" }
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - Parsing

    func videos(inListing response: SourceResponse) throws -> [Video] {
        let html = response.text
        // Every card is a list item carrying the view key as an attribute.
        let items = html.components(separatedBy: "<li ").dropFirst()
        var seen = Set<String>()
        return items.compactMap(video(inItem:)).filter { seen.insert($0.itemID).inserted }
    }

    private func video(inItem item: String) -> Video? {
        guard let key = HTMLScanner.firstMatch(of: #"data-video-vkey="([^"]+)""#, in: item) else { return nil }

        // The poster sits in `data-path`; `src` may still be a placeholder.
        let thumbnail = HTMLScanner.firstMatch(of: #"data-path="(https?://[^"]+)""#, in: item)
            ?? HTMLScanner.firstMatch(of: #"<img[^>]+src="(https?://[^"]+)""#, in: item)

        let title = HTMLScanner.firstMatch(of: #"class="thumbnailTitle"[^>]*>\s*([^<]+)"#, in: item)
            ?? HTMLScanner.firstMatch(of: #"<img[^>]+alt="([^"]*)""#, in: item)
            ?? ""

        let clock = HTMLScanner.firstMatch(of: #"class="[^"]*\btime\b[^"]*">\s*([0-9:]+)\s*<"#, in: item) ?? ""
        let views = HTMLScanner.firstMatch(of: #"class="videoViews"[^>]*>(?:<i[^>]*></i>)?\s*([^<]+)<"#, in: item) ?? ""

        return Video(
            sourceID: id,
            itemID: HTMLScanner.decode(key),
            rawTitle: HTMLScanner.decode(title.trimmingCharacters(in: .whitespacesAndNewlines)),
            thumbnailURL: thumbnail.flatMap { URL(string: HTMLScanner.decode($0)) },
            previewURL: HTMLScanner.firstMatch(of: #"data-webm="(https?://[^"]+)""#, in: item)
                .flatMap { URL(string: HTMLScanner.decode($0)) },
            duration: HTMLScanner.seconds(fromClock: clock),
            views: views.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func details(inWatchPage response: SourceResponse, itemID: String) throws -> VideoDetails {
        let html = response.text
        let config = playerConfig(in: html)
        let streams = self.streams(in: config)

        return VideoDetails(
            sources: streams,
            related: (try? videos(inListing: response))?.filter { $0.itemID != itemID } ?? [],
            video: video(from: config, streams: streams, itemID: itemID, html: html)
        )
    }

    /// Returns the `flashvars_<id>` object the page declares for its player.
    ///
    /// Decoded loosely rather than into a model: the site varies the types of
    /// several fields between videos, and a strict decode would drop the lot.
    private func playerConfig(in html: String) -> [String: Any] {
        guard let json = HTMLScanner.firstMatch(of: #"var flashvars_\d+\s*=\s*(\{.*?\});"#,
                                                in: html,
                                                dotMatchesNewlines: true),
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private func streams(in config: [String: Any]) -> [StreamSource] {
        guard let definitions = config["mediaDefinitions"] as? [[String: Any]] else { return [] }

        return definitions.compactMap { definition -> StreamSource? in
            // Only the HLS entries carry a playable URL. The MP4 entry points at
            // a `get_media` endpoint that needs a second round trip, and AVPlayer
            // prefers the HLS manifest anyway.
            guard definition["format"] as? String == "hls",
                  let urlString = definition["videoUrl"] as? String,
                  !urlString.isEmpty,
                  let url = URL(string: urlString) else {
                return nil
            }
            return StreamSource(url: url, height: integer(definition["height"]) ?? 0)
        }
        .sorted { $0.height > $1.height }
    }

    private func video(from config: [String: Any], streams: [StreamSource], itemID: String, html: String) -> Video? {
        guard let title = config["video_title"] as? String else { return nil }

        let keywords = (HTMLScanner.metaContent("keywords", in: html) ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Video(
            sourceID: id,
            itemID: itemID,
            rawTitle: HTMLScanner.decode(title),
            thumbnailURL: (config["image_url"] as? String).flatMap { URL(string: $0) },
            duration: integer(config["video_duration"]) ?? 0,
            // The watch page doesn't publish a view count anywhere reliable; the
            // listing's survives via Video.merging(_:).
            isHD: (streams.first?.height ?? 0) >= 720,
            tags: Array(keywords.prefix(12))
        )
    }

    /// Reads a value the site sometimes sends as a number and sometimes as text.
    private func integer(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let text = value as? String { return Int(text) }
        return nil
    }
}
