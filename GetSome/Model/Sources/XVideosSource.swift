/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A content source for xvideos.com.
*/

import Foundation

/// A content source for xvideos.com.
///
/// Listings are server-rendered. The watch page publishes only a 360p MP4, so
/// playback comes from the same endpoint the site's own player asks:
/// `/html5player/getvideo/<id>/<cdn>` returns a signed HLS manifest covering 250p
/// through 1080p. See ``streamsURL(forItem:)``.
///
/// Note the signature sits in a leading *path* segment rather than a query, so it
/// also covers the relative variant playlists and segments beneath it.
struct XVideosSource: ContentSource {
    let id = "xvideos"
    let displayName = "XVideos"
    let homeURL = URL(string: "https://www.xvideos.com/")!

    var feeds: [Feed] {
        [
            makeFeed("home",
                     name: String(localized: "Popular", comment: "Collection name"),
                     description: String(localized: "The front page, refreshed through the day.",
                                         comment: "The description of a collection of videos."),
                     icon: "flame"),
            makeFeed("new",
                     name: String(localized: "Just Added", comment: "Collection name"),
                     description: String(localized: "The newest uploads, in the order they arrived.",
                                         comment: "The description of a collection of videos."),
                     icon: "sparkles"),
            makeFeed("verified",
                     name: String(localized: "Verified", comment: "Collection name"),
                     description: String(localized: "Uploads from accounts the site has verified.",
                                         comment: "The description of a collection of videos."),
                     icon: "checkmark.seal")
        ]
    }

    // MARK: - URLs

    func listingURL(for feed: Feed, page: Int) -> URL? {
        guard feed.sourceID == id else { return nil }

        if feed.group == .category {
            // Zero-based, like /verified.
            return homeURL.appending(path: "tags/\(feed.slug)/\(page - 1)")
        }

        switch feed.slug {
        case "home":
            // The front page ignores a page parameter, so it's a single page. The
            // feed store notices the second page adds nothing and stops asking.
            return page == 1 ? homeURL : nil
        case "new":
            // One-based: /new/0 is a 404.
            return homeURL.appending(path: "new/\(page)")
        case "verified":
            // Zero-based, unlike /new.
            return homeURL.appending(path: "verified/videos/\(page - 1)")
        default:
            return nil
        }
    }

    func searchURL(query: String, page: Int) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components = URLComponents(url: homeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "k", value: trimmed),
            URLQueryItem(name: "p", value: String(page - 1))
        ]
        return components.url
    }

    /// The site lists every tag on one page, with a video count for each.
    func categoriesURL() -> URL? {
        homeURL.appending(path: "tags")
    }

    func categories(in response: SourceResponse) throws -> [Feed] {
        let html = response.text
        let pattern = #"<li><a href="/tags/([^"/]+)"><b>([^<]*)</b>(?:<span[^>]*>([^<]*)</span>)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }

        var seen = Set<String>()
        return expression.matches(in: html, range: NSRange(html.startIndex..., in: html))
            .compactMap { match -> Feed? in
                guard let slugRange = Range(match.range(at: 1), in: html) else { return nil }
                let slug = String(html[slugRange])
                // The A–Z jump links are single letters pointing at the same page.
                guard slug.count > 1, seen.insert(slug).inserted else { return nil }

                let name = Range(match.range(at: 2), in: html)
                    .map { HTMLScanner.decode(String(html[$0])).trimmingCharacters(in: .whitespaces) } ?? slug
                let count = Range(match.range(at: 3), in: html)
                    .map { String(html[$0]).trimmingCharacters(in: .whitespaces) } ?? ""

                return makeFeed(
                    slug,
                    name: name.isEmpty ? slug : name,
                    description: count.isEmpty
                        ? ""
                        : String(localized: "\(count) videos", comment: "A category's video count"),
                    icon: "tag",
                    group: .category
                )
            }
    }

    func watchURL(forItem itemID: String) -> URL {
        // The slug after the identifier is decorative; the site resolves the id.
        homeURL.appending(path: "video.\(itemID)/x")
    }

    // MARK: - Parsing

    func videos(inListing response: SourceResponse) throws -> [Video] {
        let html = response.text
        let blocks = html.components(separatedBy: "<div id=\"video_").dropFirst()
        var seen = Set<String>()
        return blocks.compactMap(video(inBlock:)).filter { seen.insert($0.itemID).inserted }
    }

    private func video(inBlock block: String) -> Video? {
        guard let key = HTMLScanner.firstMatch(of: #"data-eid="([^"]+)""#, in: block) else { return nil }

        // The anchor's title attribute is the clean title; the link text has the
        // duration appended to it.
        let title = HTMLScanner.firstMatch(of: #"<p class="title"><a[^>]+title="([^"]*)""#, in: block)
            ?? HTMLScanner.firstMatch(of: #"<img[^>]+alt="([^"]*)""#, in: block)
            ?? ""

        let duration = HTMLScanner.firstMatch(of: #"<span class="duration">([^<]+)</span>"#, in: block) ?? ""
        let views = HTMLScanner.firstMatch(of: #"([0-9][0-9.,]*[kKmM]?)\s*<span class="sprfluous">\s*Views"#, in: block) ?? ""

        return Video(
            sourceID: id,
            itemID: HTMLScanner.decode(key),
            rawTitle: HTMLScanner.decode(title),
            thumbnailURL: HTMLScanner.firstMatch(of: #"data-src="(https?://[^"]+)""#, in: block)
                .flatMap { URL(string: HTMLScanner.decode($0)) },
            previewURL: HTMLScanner.firstMatch(of: #"data-pvv="(https?://[^"]+)""#, in: block)
                .flatMap { URL(string: HTMLScanner.decode($0)) },
            duration: Self.seconds(fromWords: duration),
            views: views.trimmingCharacters(in: .whitespacesAndNewlines),
            isHD: block.contains("hd-mark") || block.contains(">1080p<") || block.contains(">720p<")
        )
    }

    func details(inWatchPage response: SourceResponse, itemID: String) throws -> VideoDetails {
        let html = response.text
        let streams = self.streams(in: html)

        return VideoDetails(
            sources: streams,
            related: related(inWatchPage: html).filter { $0.itemID != itemID },
            video: video(inWatchPage: html, streams: streams, itemID: itemID)
        )
    }

    /// Returns the related videos the watch page declares.
    ///
    /// The watch page carries no video markup at all — related videos arrive as a
    /// JSON array assigned to `video_related`, so the listing parser finds nothing
    /// here and this reads the array instead.
    private func related(inWatchPage html: String) -> [Video] {
        guard let raw = HTMLScanner.firstMatch(of: #"var\s+video_related\s*=\s*(\[.*?\]);"#,
                                               in: html,
                                               dotMatchesNewlines: true),
              let data = raw.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return entries.compactMap { entry in
            guard let key = entry["eid"] as? String, !key.isEmpty else { return nil }
            let title = (entry["tf"] as? String) ?? (entry["t"] as? String) ?? ""
            // `h`, `hm` and `hp` are the site's high-definition markers.
            let isHD = ["h", "hm", "hp"].contains { (entry[$0] as? Int ?? 0) > 0 }

            return Video(
                sourceID: id,
                itemID: key,
                rawTitle: HTMLScanner.decode(title),
                thumbnailURL: (entry["i"] as? String).flatMap { URL(string: $0) },
                duration: Self.seconds(fromWords: (entry["d"] as? String) ?? ""),
                views: (entry["n"] as? String) ?? "",
                isHD: isHD
            )
        }
    }

    /// The endpoint the site's own player asks for playable URLs.
    ///
    /// The watch page carries a single 360p MP4; this returns the adaptive HLS
    /// manifest covering 250p through 1080p. The identifier in the path is the
    /// same one the app already uses, and `21` is the CDN the page nominates.
    func streamsURL(forItem itemID: String) -> URL? {
        homeURL.appending(path: "html5player/getvideo/\(itemID)/\(Self.cdnIdentifier)")
    }

    private static let cdnIdentifier = "21"

    func streams(in response: SourceResponse) throws -> [StreamSource] {
        guard let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            return []
        }

        // The manifest is adaptive, so its height is left unknown deliberately:
        // the player picks a rendition per its bandwidth and the quality setting,
        // rather than the app pinning one up front.
        if let hls = object["hls"] as? String, let url = URL(string: hls) {
            return [StreamSource(url: url, height: 0)]
        }

        // No manifest — fall back to whatever fixed renditions it offered.
        return ["mp4_high": 360, "mp4_low": 240]
            .compactMap { key, height in
                guard let text = object[key] as? String, let url = URL(string: text) else { return nil }
                return StreamSource(url: url, height: height)
            }
            .sorted { $0.height > $1.height }
    }

    /// Returns the signed media URLs the watch page publishes.
    private func streams(in html: String) -> [StreamSource] {
        let pattern = #"https?://[^\s"'<>]+/video_(\d+)p\.mp4\?[^\s"'<>]*"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(html.startIndex..., in: html)
        var streams = [StreamSource]()
        var seen = Set<URL>()

        for match in expression.matches(in: html, range: range) {
            guard let whole = Range(match.range, in: html),
                  let heightRange = Range(match.range(at: 1), in: html) else { continue }
            let text = String(html[whole])
            // The `sfw` rendition is a censored teaser, not the video.
            guard !text.contains("sfw"), let url = URL(string: text), seen.insert(url).inserted else { continue }
            streams.append(StreamSource(url: url, height: Int(html[heightRange]) ?? 0))
        }
        return streams.sorted { $0.height > $1.height }
    }

    private func video(inWatchPage html: String, streams: [StreamSource], itemID: String) -> Video? {
        guard let title = HTMLScanner.firstMatch(of: #"html5player\.setVideoTitle\('(.*?)'\);"#, in: html) else {
            return nil
        }
        let duration = HTMLScanner.firstMatch(of: #"html5player\.setVideoFullDuration\((\d+)\)"#, in: html)

        return Video(
            sourceID: id,
            itemID: itemID,
            rawTitle: HTMLScanner.decode(title),
            thumbnailURL: HTMLScanner.firstMatch(of: #"html5player\.setThumbUrl\('([^']+)'\)"#, in: html)
                .flatMap { URL(string: $0) },
            duration: duration.flatMap(Int.init) ?? 0,
            isHD: (streams.first?.height ?? 0) >= 720
        )
    }

    /// Converts a written duration such as `10 min` or `1 h 23 min` into seconds.
    ///
    /// The site writes durations in words rather than as a clock, so the shared
    /// `HTMLScanner.seconds(fromClock:)` doesn't apply.
    static func seconds(fromWords text: String) -> Int {
        var total = 0
        var value = 0
        for token in text.lowercased().split(whereSeparator: { $0 == " " || $0 == "\u{00a0}" }) {
            if let number = Int(token) {
                value = number
                continue
            }
            switch token.first {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            default: break
            }
            value = 0
        }
        return total
    }
}

// MARK: - Signing in

/// Signing in to xvideos.
///
/// The sign-in form posts back to the same page it's served from, carrying a
/// one-time `csrf_token` that only exists on that page — so a sign-in is always
/// two requests: fetch the form, then post it.
///
/// Notably the form itself has no CAPTCHA. The page has one, but it belongs to the
/// sign-up and lost-password forms; the sign-in fieldset has none.
extension XVideosSource: AuthenticatingSource {
    var signInURL: URL { homeURL.appending(path: "account") }

    func signInToken(in html: String) -> String? {
        // `value` comes before `name` in the markup, and the page carries a second
        // csrf_token for the lost-password form — so this anchors on the field name
        // and reads backwards, rather than taking the first token it sees.
        HTMLScanner.firstMatch(
            of: #"value="([^"]*)"[^>]*name="signin-form\[csrf_token\]""#, in: html
        )
    }

    func signInBody(username: String, password: String, token: String) -> Data {
        // The site names every field with a `signin-form[...]` prefix, and sends the
        // empty hidden fields too — a partial form is rejected.
        let fields = [
            ("signin-form[csrf_token]", token),
            ("signin-form[votes]", ""),
            ("signin-form[subs]", ""),
            ("signin-form[post_referer]", ""),
            ("signin-form[login]", username),
            ("signin-form[password]", password),
            ("signin-form[rememberme]", "1")
        ]
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.map { name, value in
            let key = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    func isSignedIn(in html: String) -> Bool {
        // The sign-in form is served to anyone who isn't signed in — including on
        // the account pages themselves — so its absence is the signal.
        !html.contains("signin-form[password]")
    }
}
