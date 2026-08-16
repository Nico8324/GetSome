/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A content source for missav.ws.
*/

import Foundation

/// A content source for missav.ws.
///
/// Listings are server-rendered, and the site publishes titles in whichever of its
/// locales the path names — see ``localePath``. That means most text arrives already
/// in the reader's language, so `TranslationStore` has far less to do here than for
/// a single-language site.
///
/// Playback is a two-step read of one page. The watch page assembles its media URL
/// in a `p,a,c,k,e,d` block, but nothing is actually concealed: the same identifier
/// appears in plain text in the seek-thumbnail URLs, so ``details(inWatchPage:itemID:)``
/// reads it there and builds the master playlist rather than unpacking anything.
struct MissAVSource: ContentSource {
    let id = "missav"
    let displayName = "MissAV"
    let homeURL = URL(string: "https://missav.ws/")!

    var feeds: [Feed] {
        [
            makeFeed("home",
                     name: String(localized: "Popular", comment: "Collection name"),
                     description: String(localized: "The front page, refreshed through the day.",
                                         comment: "The description of a collection of videos."),
                     icon: "flame",
                     kind: .popular),
            makeFeed("new",
                     name: String(localized: "Just Added", comment: "Collection name"),
                     description: String(localized: "The newest uploads, in the order they arrived.",
                                         comment: "The description of a collection of videos."),
                     icon: "sparkles",
                     kind: .latest),
            makeFeed("release",
                     name: String(localized: "New Releases", comment: "Collection name"),
                     description: String(localized: "Titles by their release date.",
                                         comment: "The description of a collection of videos."),
                     icon: "calendar.badge.plus",
                     kind: .newReleases),
            makeFeed("uncensored-leak",
                     name: String(localized: "Uncensored", comment: "Collection name"),
                     description: String(localized: "Uncensored releases.",
                                         comment: "The description of a collection of videos."),
                     icon: "eye",
                     kind: .uncensored),
            makeFeed("english-subtitle",
                     name: String(localized: "English Subtitles", comment: "Collection name"),
                     description: String(localized: "Titles carrying English subtitles.",
                                         comment: "The description of a collection of videos."),
                     icon: "captions.bubble",
                     kind: .englishSubtitles),
            makeFeed("chinese-subtitle",
                     name: String(localized: "Chinese Subtitles", comment: "Collection name"),
                     description: String(localized: "Titles carrying Chinese subtitles.",
                                         comment: "The description of a collection of videos."),
                     icon: "character.bubble",
                     kind: .chineseSubtitles),
            makeFeed("today-hot",
                     name: String(localized: "Most Viewed Today", comment: "Collection name"),
                     description: String(localized: "The most-watched videos of the past day.",
                                         comment: "The description of a collection of videos."),
                     icon: "calendar.badge.clock",
                     group: .chart,
                     kind: .topDay),
            makeFeed("weekly-hot",
                     name: String(localized: "Most Viewed This Week", comment: "Collection name"),
                     description: String(localized: "The most-watched videos of the past seven days.",
                                         comment: "The description of a collection of videos."),
                     icon: "calendar",
                     group: .chart,
                     kind: .topWeek),
            makeFeed("monthly-hot",
                     name: String(localized: "Most Viewed This Month", comment: "Collection name"),
                     description: String(localized: "The most-watched videos of the past month.",
                                         comment: "The description of a collection of videos."),
                     icon: "chart.line.uptrend.xyaxis",
                     group: .chart,
                     kind: .topMonth)
        ]
    }

    // MARK: - Locale

    /// The locales the site publishes, as they appear in its paths.
    ///
    /// The site names Chinese `cn` rather than `zh`, which is the only code that
    /// doesn't match the language identifier it corresponds to.
    private static let siteLocales: Set<String> = [
        "cn", "de", "en", "fr", "id", "ja", "ko", "ms", "pt", "th", "vi"
    ]

    /// The locale segment every path on this site begins with.
    ///
    /// Titles, genre names and section headings all come back in this language, so
    /// following the device rather than pinning `en` means the catalog reads in the
    /// reader's own language before translation is considered at all.
    static var localePath: String {
        let code = Locale.preferredLanguages.first
            .flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
        if code == "zh" { return "cn" }
        return siteLocales.contains(code) ? code : "en"
    }

    // MARK: - URLs

    func listingURL(for feed: Feed, page: Int) -> URL? {
        guard feed.sourceID == id else { return nil }

        if feed.group == .category {
            // Genre slugs arrive percent-encoded and some contain a slash — "3P / 4P"
            // is one — so they're pasted in rather than appended as a path component,
            // which would encode them a second time.
            return url(forPath: "genres/\(feed.slug)", page: page)
        }

        // The front page takes no page parameter, so it's a single page. The feed
        // store notices the second page adds nothing and stops asking.
        if feed.slug == "home" {
            return page == 1 ? homeURL.appending(path: Self.localePath) : nil
        }
        return url(forPath: feed.slug, page: page)
    }

    /// The site takes its query as a path component, with words joined by `+`.
    ///
    /// The separator matters more than it looks: `%20` drops a two-word English query
    /// to a single result, and `-` returns nothing at all for an accented one. Only
    /// `+` answers properly for both.
    func searchURL(query: String, page: Int) -> URL? {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let encoded = words
            .compactMap { $0.addingPercentEncoding(withAllowedCharacters: allowed) }
            .joined(separator: "+")
        guard !encoded.isEmpty else { return nil }

        return url(forPath: "search/\(encoded)", page: page)
    }

    /// The site lists every genre on one page.
    func categoriesURL() -> URL? {
        homeURL.appending(path: "\(Self.localePath)/genres")
    }

    func watchURL(forItem itemID: String) -> URL {
        homeURL.appending(path: "\(Self.localePath)/\(itemID)")
    }

    /// Builds a locale-prefixed URL, adding the one-based page the site expects.
    ///
    /// The path is inserted rather than appended because callers pass segments that
    /// are already percent-encoded.
    private func url(forPath path: String, page: Int) -> URL? {
        guard var components = URLComponents(
            string: "\(homeURL.absoluteString)\(Self.localePath)/\(path)"
        ) else { return nil }
        if page > 1 {
            components.queryItems = [URLQueryItem(name: "page", value: String(page))]
        }
        return components.url
    }

    // MARK: - Parsing

    func categories(in response: SourceResponse) throws -> [Feed] {
        let html = response.text
        // Any locale's prefix is accepted so a stale link shape doesn't drop the list.
        let pattern = #"href="[^"]*?/genres/([^"]+)""#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }

        var seen = Set<String>()
        return expression.matches(in: html, range: NSRange(html.startIndex..., in: html))
            .compactMap { match -> Feed? in
                guard let range = Range(match.range(at: 1), in: html) else { return nil }
                let slug = String(html[range])
                guard seen.insert(slug).inserted else { return nil }

                // The slug is the genre's own localized name, percent-encoded.
                let name = slug.removingPercentEncoding ?? slug
                return makeFeed(slug,
                                name: HTMLScanner.decode(name),
                                description: "",
                                icon: "tag",
                                group: .category)
            }
    }

    func videos(inListing response: SourceResponse) throws -> [Video] {
        let html = response.text
        let blocks = html.components(separatedBy: "\"thumbnail group\"").dropFirst()
        var seen = Set<String>()
        return blocks.compactMap(video(inBlock:)).filter { seen.insert($0.itemID).inserted }
    }

    private func video(inBlock block: String) -> Video? {
        // The cover URL carries the catalog code, which is also the item identifier.
        guard let code = HTMLScanner.firstMatch(of: #"fourhoi\.com/([a-z0-9][a-z0-9\-]*)/cover"#, in: block) else {
            return nil
        }

        // The caption below the card leads with the code; the image's alt text is the
        // same title without it. Prefer the caption, since the code is worth showing.
        let title = HTMLScanner.firstMatch(of: #"truncate">\s*<a[^>]*>\s*(.*?)\s*</a>"#,
                                           in: block,
                                           dotMatchesNewlines: true)
            ?? HTMLScanner.firstMatch(of: #"<img[^>]+alt="([^"]*)""#, in: block)
            ?? code

        let duration = HTMLScanner.firstMatch(of: #"<span class="absolute bottom-1 right-1[^"]*">\s*([\d:]+)\s*</span>"#,
                                              in: block) ?? ""

        return Video(
            sourceID: id,
            itemID: code,
            rawTitle: HTMLScanner.decode(title),
            // cover-n, not cover-t: the CDN keeps both for every title, and the
            // "t" render is a genuine thumbnail — too small for a card, let alone
            // the hero banner.
            thumbnailURL: Self.assetURL(code, file: "cover-n.jpg"),
            previewURL: Self.assetURL(code, file: "preview.mp4"),
            duration: HTMLScanner.seconds(fromClock: duration)
        )
    }

    /// The CDN that serves this site's covers and hover previews.
    private static func assetURL(_ code: String, file: String) -> URL? {
        URL(string: "https://fourhoi.com/\(code)/\(file)")
    }

    func details(inWatchPage response: SourceResponse, itemID: String) throws -> VideoDetails {
        let html = response.text

        return VideoDetails(
            sources: streams(inWatchPage: html),
            related: ((try? videos(inListing: response)) ?? []).filter { $0.itemID != itemID },
            video: video(inWatchPage: html, itemID: itemID),
            sceneThumbnailURLs: sceneThumbnailURLs(inWatchPage: html)
        )
    }

    /// Returns the master playlist for the video the watch page presents.
    ///
    /// The page's packed script builds this URL, but unpacking it isn't necessary:
    /// the identifier it assembles also appears verbatim in the seek-thumbnail URLs
    /// alongside it, which is where this reads it from.
    ///
    /// The height is left at zero because the playlist is adaptive; the client
    /// expands it into one source per rendition.
    private func streams(inWatchPage html: String) -> [StreamSource] {
        // The seek-thumbnail URLs sit inside a JSON string, so their separators are
        // escaped — `surrit.com\/<id>` rather than `surrit.com/<id>`.
        let pattern = #"surrit\.com\\?/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"#
        guard let identifier = HTMLScanner.firstMatch(of: pattern, in: html),
              let url = URL(string: "https://surrit.com/\(identifier)/playlist.m3u8") else {
            return []
        }
        return [StreamSource(url: url, height: 0)]
    }

    private func video(inWatchPage html: String, itemID: String) -> Video? {
        let title = HTMLScanner.metaContent("og:title", in: html)
            ?? HTMLScanner.firstMatch(of: #"<h1[^>]*>\s*(.*?)\s*</h1>"#, in: html, dotMatchesNewlines: true)
        guard let title else { return nil }

        let date = HTMLScanner.firstMatch(of: #"<time[^>]*>\s*(\d{4}-\d{2}-\d{2})\s*</time>"#, in: html)

        return Video(
            sourceID: id,
            itemID: itemID,
            rawTitle: HTMLScanner.decode(title),
            thumbnailURL: Self.assetURL(itemID, file: "cover-n.jpg"),
            tags: genres(inWatchPage: html),
            uploadDate: date.flatMap { Date.siteFormatter.date(from: $0) }
        )
    }

    /// Returns the genres the watch page lists for this video, as displayed.
    ///
    /// Matching every `/genres/` link would also collect the site's navigation menu,
    /// which offers a couple of genres of its own — they'd arrive as tags on every
    /// video regardless of subject. The video's own row is the one whose links carry
    /// the highlight class, and the label beside it is localized, so it can't be the
    /// anchor instead.
    private func genres(inWatchPage html: String) -> [String] {
        let pattern = #"href="[^"]*?/genres/([^"]+)"\s+class="text-nord13"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }

        var seen = Set<String>()
        return expression.matches(in: html, range: NSRange(html.startIndex..., in: html))
            .compactMap { match -> String? in
                guard let range = Range(match.range(at: 1), in: html) else { return nil }
                let slug = String(html[range])
                guard seen.insert(slug).inserted else { return nil }
                return HTMLScanner.decode(slug.removingPercentEncoding ?? slug)
            }
    }

    /// Returns scene preview thumbnails for timeline scrubbing, if the watch page provides them.
    ///
    /// The page publishes seek-thumbnail URLs for timeline preview, sitting alongside
    /// the playlist identifier in a JSON string with escaped separators. Individual
    /// thumbnail URLs are extracted here; if only a single sprite sheet is found
    /// rather than a sequence of scene images, an empty array is returned.
    private func sceneThumbnailURLs(inWatchPage html: String) -> [URL] {
        // Look for complete URLs containing surrit.com/<uuid>/... in the HTML, handling
        // both escaped (/) and unescaped (\/) slashes from JSON context.
        // The pattern captures URLs between quotes, which is where they appear in HTML.
        let pattern = #"\"(https?:\\?\/\\?\/surrit\.com\\?\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\?\/[^\"\s\\]+)\""#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }

        var urls: [URL] = []
        var seen = Set<String>()

        let matches = expression.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for match in matches {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            var urlString = String(html[range])

            // Unescape forward slashes from JSON encoding
            urlString = urlString.replacingOccurrences(of: "\\/", with: "/")

            // Filter out likely sprite sheets or non-image URLs
            if urlString.contains("vtt") || urlString.contains("sprite") {
                continue
            }

            guard seen.insert(urlString).inserted,
                  let url = URL(string: urlString) else { continue }

            urls.append(url)
        }

        // If we found only one URL, it's likely a single sprite sheet rather than a
        // sequence of scene images — skip it as instructed.
        if urls.count <= 1 {
            return []
        }

        // Sample evenly down to 12 if more are available, preserving chronological order
        if urls.count > 12 {
            let step = urls.count / 12
            return stride(from: 0, to: urls.count, by: step).prefix(12).compactMap { urls[$0] }
        }

        return urls
    }
}
