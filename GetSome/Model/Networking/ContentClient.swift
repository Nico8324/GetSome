/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Loads the app's video content from whichever source publishes it.
*/

import Foundation
import OSLog

/// Loads the app's video content from whichever source publishes it.
///
/// The client knows how to make a request and cache a result. Everything
/// site-specific — routing, markup, stream selection — lives behind
/// ``ContentSource``, so this type never changes when the app gains a site.
actor ContentClient {
    static let shared = ContentClient()

    private let logger = Logger(subsystem: "com.getsome.GetSome", category: "Content")
    private let session: URLSession

    /// Resolved details, keyed by ``Video/id``.
    ///
    /// Sites commonly sign their media URLs with an expiration, so the app only
    /// holds on to resolved details briefly.
    private var resolvedDetails = [VideoID: (details: VideoDetails, date: Date)]()
    private let cacheLifetime: TimeInterval = 10 * 60

    /// Recently fetched poster bytes, oldest first in `imageOrder`.
    private var imageCache = [URL: Data]()
    private var imageOrder = [URL]()
    private let imageCacheLimit = 300

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.requestCachePolicy = .reloadRevalidatingCacheData
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 30
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Loads a page of videos from the specified feed.
    /// - Parameters:
    ///   - feed: The feed to load. Its source must be one the app knows.
    ///   - page: A one-based page number.
    func videos(for feed: Feed, page: Int = 1) async throws -> [Video] {
        let source = try source(of: feed)
        // Asked of `listingRequest`, not `listingURL`: a feed that is a POST has no
        // listing URL at all, and checking the URL first declared it unsupported
        // before the request it does have was ever built.
        guard let pageRequest = source.listingRequest(for: feed, page: page),
              let url = pageRequest.url else {
            throw ContentError.unsupportedFeed(feed.name)
        }
        // A signed-in feed is fetched on the authenticator's session, which carries
        // the login cookies — and, just as deliberately, doesn't record anything to
        // RequestLog. See SourceAuthenticator.
        if source.requiresSignIn(feed), let account = source as? any AuthenticatingSource {
            let (response, status) = try await SourceAuthenticator.shared.page(for: pageRequest, from: account)
            let videos = try source.videos(inListing: response)
            if videos.isEmpty {
                // Also to the system log, marked public so it survives redaction.
                // Reading a diagnostics screen through screenshots is slower and
                // less reliable than reading the log, and this line is the schema,
                // not the contents — see `shape(of:)`.
                logger.error("account feed \(feed.slug, privacy: .public): \(Self.shape(of: response.text), privacy: .public)")
            }
            // Recorded without its body, unlike every other request. An empty
            // account feed is otherwise unreadable: a page that parses to nothing
            // looks identical to an account with nothing in it, and the byte count
            // is what separates them. The body itself is somebody's account page,
            // and diagnostics reports are made to be sent to other people.
            await RequestLog.shared.record(
                RequestRecord(sourceID: source.id, intent: "\(feed.name) p\(page)", url: url,
                              statusCode: status, byteCount: response.data.count,
                              parsedCount: videos.count,
                              failure: videos.isEmpty ? Self.shape(of: response.text) : nil,
                              date: .now)
            )
            // Held to the same rule as every other feed: a first page that parses to
            // nothing is reported, not shown as an empty shelf. These two pages build
            // themselves in JavaScript, so this currently always fires — and saying so
            // is the point. An empty feed would read as "you have no favorites".
            if videos.isEmpty, page == 1 {
                throw ContentError.noResults(source.displayName)
            }
            return videos
        }

        let response = try await fetch(url, from: source, intent: "\(feed.name) p\(page)")
        let videos = try source.videos(inListing: response)
        try note(videos.count, for: response, intent: "\(feed.name) p\(page)", source: source, page: page)
        return videos
    }

    /// Loads a page of videos that match the specified text.
    /// - Parameters:
    ///   - query: The text to search for.
    ///   - sourceID: The site to search.
    ///   - page: A one-based page number.
    func videos(matching query: String, in sourceID: String, page: Int = 1) async throws -> [Video] {
        let source = try source(with: sourceID)
        guard source.supportsSearch else {
            throw ContentError.searchUnavailable(source.displayName)
        }
        guard let url = source.searchURL(query: query, page: page) else { return [] }
        let response = try await fetch(url, from: source, intent: "search “\(query)” p\(page)")
        let videos = try source.videos(inListing: response)
        try note(videos.count, for: response, intent: "search “\(query)” p\(page)", source: source, page: page)
        return videos
    }

    /// Loads the categories a source publishes.
    ///
    /// Returns an empty list for a source without a category index rather than
    /// throwing — having none is a normal state, not a failure.
    func categories(for sourceID: String) async throws -> [Feed] {
        let source = try source(with: sourceID)
        guard let url = source.categoriesURL() else { return [] }
        let response = try await fetch(url, from: source, intent: "categories")
        return try source.categories(in: response)
    }

    /// Loads the playback sources and related videos for the specified video.
    func details(for video: Video) async throws -> VideoDetails {
        if let cached = resolvedDetails[video.id], Date.now.timeIntervalSince(cached.date) < cacheLifetime {
            return cached.details
        }
        let source = try source(with: video.sourceID)
        let response = try await fetch(source.watchURL(forItem: video.itemID), from: source, intent: "details")
        var details = try source.details(inWatchPage: response, itemID: video.itemID)

        // A watch page can publish a master playlist directly, in which case there's
        // no second endpoint to call — expand it here too, so the quality setting and
        // the reported height mean the same thing for those sites as for the rest.
        // Left as `try?`: a manifest that won't load is worth falling back on, not
        // worth failing the whole detail page for.
        if let expanded = try? await expandingManifest(in: details.sources, from: source) {
            details.sources = expanded
        }

        // Some sites hand the watch page only a token rendition and serve the real
        // set from a second endpoint. Prefer that when it answers, since it's what
        // the site's own player uses.
        if let url = source.streamsURL(forItem: video.itemID) {
            do {
                let streamResponse = try await fetch(url, from: source, intent: "streams")
                var streams = try source.streams(in: streamResponse)
                streams = try await expandingManifest(in: streams, from: source)
                if !streams.isEmpty { details.sources = streams }
            } catch {
                logger.error("Stream lookup for \(video.id.description, privacy: .public) failed: \(error.localizedDescription)")
            }
        }

        resolvedDetails[video.id] = (details, .now)
        return details
    }

    /// Returns the stream to play for the specified video.
    ///
    /// Sources publish several resolutions; each one decides which to prefer. The
    /// whole ``StreamSource`` comes back rather than just its URL so the player can
    /// report the height it's actually playing.
    func stream(for video: Video) async throws -> StreamSource {
        let source = try source(with: video.sourceID)
        let details = try await details(for: video)
        guard let stream = source.preferredStream(from: details.sources) else {
            throw ContentError.noPlayableSource
        }
        return stream
    }

    /// Replaces a lone master playlist with the renditions it advertises.
    ///
    /// Left as-is, an adaptive manifest has no height, so the app can't say what
    /// it's playing and the Maximum Quality setting has nothing to compare against.
    private func expandingManifest(
        in streams: [StreamSource],
        from source: any ContentSource
    ) async throws -> [StreamSource] {
        guard streams.count == 1,
              let manifest = streams.first,
              manifest.height == 0,
              manifest.url.pathExtension.lowercased() == "m3u8" else {
            return streams
        }

        let response = try await fetch(manifest.url, from: source, intent: "manifest")
        let renditions = HLSManifest.streams(in: response.text, relativeTo: manifest.url)
        // A media playlist lists segments rather than alternatives; play it directly.
        return renditions.isEmpty ? streams : renditions
    }

    /// Downloads an image the way its source expects, such as a poster.
    ///
    /// This goes through the source's own `request(for:)` rather than a bare
    /// fetch: at least one site's image CDN answers 403 without a user agent and
    /// referer, which is invisible until posters start coming up blank.
    func imageData(at url: URL, from sourceID: String) async -> Data? {
        if let cached = imageCache[url] { return cached }

        let request = ContentSources.source(with: sourceID)?.request(for: url) ?? URLRequest(url: url)
        guard let data = try? await session.data(for: request).0, !data.isEmpty else { return nil }

        imageCache[url] = data
        imageOrder.append(url)
        if imageOrder.count > imageCacheLimit {
            imageCache.removeValue(forKey: imageOrder.removeFirst())
        }
        return data
    }

    /// Discards everything the client has cached.
    func clearCache() {
        resolvedDetails.removeAll()
        imageCache.removeAll()
        imageOrder.removeAll()
    }

    // MARK: - Requests

    private func fetch(
        _ url: URL,
        from source: any ContentSource,
        intent: String
    ) async throws -> SourceResponse {
        let data: Data
        let status: Int?
        let finalURL: URL
        do {
            let (body, response) = try await session.data(for: source.request(for: url))
            data = body
            status = (response as? HTTPURLResponse)?.statusCode
            finalURL = response.url ?? url
        } catch {
            await RequestLog.shared.record(
                RequestRecord(sourceID: source.id, intent: intent, url: url, statusCode: nil,
                              byteCount: 0, parsedCount: nil, failure: error.localizedDescription,
                              date: .now)
            )
            throw error
        }

        if let status, !(200..<300).contains(status) {
            logger.error("Request for \(url.absoluteString, privacy: .public) failed: \(status)")
            await RequestLog.shared.record(
                RequestRecord(sourceID: source.id, intent: intent, url: url, statusCode: status,
                              byteCount: data.count, parsedCount: nil,
                              failure: "bad response", date: .now)
            )
            throw ContentError.badResponse(status)
        }
        guard !data.isEmpty else { throw ContentError.unreadablePage }

        if Self.isRedirectHome(requested: url, final: finalURL, source: source) {
            logger.error("Request for \(url.absoluteString, privacy: .public) was sent to the home page")
            await RequestLog.shared.record(
                RequestRecord(sourceID: source.id, intent: intent, url: url, statusCode: status,
                              byteCount: data.count, parsedCount: nil,
                              failure: "redirected home", date: .now)
            )
            throw ContentError.redirectedHome(source.displayName)
        }

        lastResponse = (source.id, intent, url, status, data)
        return SourceResponse(url: finalURL, data: data)
    }

    /// Describes what a page is built from, without keeping any of it.
    ///
    /// An account page that parses to nothing can't be diagnosed from a byte count,
    /// and its body is somebody's account — the one thing a shareable diagnostics
    /// report shouldn't carry. Counting the markers a parser looks for says which
    /// kind of page arrived (videos, playlists, channels) and nothing about whose.
    private static func shape(of html: String) -> String {
        // A JSON answer is described by its keys. Values are the account's contents;
        // the key names are the site's schema, and the schema is what's missing.
        if let data = html.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            var described = "json " + Self.keys(of: object, depth: 0).joined(separator: " ")
            // `metadata` is counters and flags — isLogged, nbLists, page — with no
            // account content in it, and its values are exactly what distinguishes
            // "not signed in" from "nothing to list". Everything else stays keys only.
            if let root = object as? [String: Any],
               let metadata = root["metadata"] as? [String: Any] {
                let values = metadata.keys.sorted().map { "\($0)=\(metadata[$0] ?? "")" }
                described += " · metadata: " + values.joined(separator: " ")
            }
            return described
        }
        let markers = [
            ("video-blocks", "<div id=\"video_"),
            ("eid", "data-eid="),
            ("playlist-links", "href=\"/playlist"),
            ("favourite-links", "href=\"/favorite"),
            ("profile-links", "href=\"/profiles/"),
            ("channel-links", "href=\"/channels/"),
            ("thumb-blocks", "class=\"thumb")
        ]
        let found = markers
            .map { ($0.0, html.components(separatedBy: $0.1).count - 1) }
            .filter { $0.1 > 0 }
            .map { "\($0.0)=\($0.1)" }

        // A page with no content markers is usually rendered by its own JavaScript,
        // which means the data comes from somewhere else. Naming the endpoints it
        // references turns "this parser can't work" into "call this instead".
        // These are paths in the site's code, not anything about the account.
        let endpoints = Self.endpointPaths(in: html)
        let parts = [
            found.isEmpty ? "no recognizable blocks" : "shape: " + found.joined(separator: " "),
            endpoints.isEmpty ? "" : "endpoints: " + endpoints.joined(separator: " ")
        ].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    /// Names the keys of a JSON answer, and nothing else it contains.
    private static func keys(of object: Any, depth: Int) -> [String] {
        // Five, not three: the interesting object is usually root → data → collection
        // → element → its fields, and a limit of three rendered that element as "[]",
        // which reads identically to an empty collection.
        guard depth < 5 else { return [] }
        switch object {
        case let dictionary as [String: Any]:
            return dictionary.keys.sorted().flatMap { key -> [String] in
                let nested = Self.keys(of: dictionary[key] ?? "", depth: depth + 1)
                return nested.isEmpty ? [key] : ["\(key){\(nested.prefix(40).joined(separator: ","))}"]
            }
        case let array as [Any]:
            // One element is enough to learn the element type's shape.
            return array.first.map { ["[\(Self.keys(of: $0, depth: depth + 1).prefix(40).joined(separator: ","))]"] } ?? ["[]"]
        default:
            return []
        }
    }

    /// The data endpoints a client-rendered page references.
    private static func endpointPaths(in html: String) -> [String] {
        let pattern = #"["'](/[a-zA-Z0-9/_.-]*(?:ajax|json|api|playlist|subscription)[a-zA-Z0-9/_.-]*)["']"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        var seen = Set<String>()
        for match in expression.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let path = String(html[range])
            // Skip stylesheets and images; they're never the data source.
            guard !path.hasSuffix(".css"), !path.hasSuffix(".png"), !path.hasSuffix(".jpg") else { continue }
            seen.insert(path)
            if seen.count >= 6 { break }
        }
        return seen.sorted()
    }

    /// Returns whether a site answered with its home page instead of the page asked for.
    ///
    /// A site that withholds its catalog by region tends to redirect every listing to
    /// the front page rather than refuse outright. That arrives as a perfectly healthy
    /// 200 full of videos, so neither the status check nor the parse count notices —
    /// every feed quietly shows the same home page under a different name.
    ///
    /// Only a redirect *to the root* counts. Sites redirect for ordinary reasons —
    /// adding a trailing slash, resolving a shortened path — and treating those as
    /// failures would break working sources.
    private static func isRedirectHome(requested: URL, final: URL, source: any ContentSource) -> Bool {
        func path(_ url: URL) -> String {
            let trimmed = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return trimmed
        }
        // Asking for the home page and receiving it is not a redirect.
        guard !path(requested).isEmpty || requested.query() != nil else { return false }
        guard path(final).isEmpty, final.query() == nil else { return false }
        // Same site, so a redirect to a different host isn't misread as this.
        return final.host() == source.homeURL.host()
    }

    /// The most recent successful fetch, held so its parse result can be recorded.
    private var lastResponse: (sourceID: String, intent: String, url: URL, status: Int?, data: Data)?

    /// Records what the parser made of a response, and keeps the page when it
    /// found nothing — that's the case worth sending to whoever maintains the source.
    private func note(
        _ count: Int,
        for response: SourceResponse,
        intent: String,
        source: any ContentSource,
        page: Int
    ) throws {
        let status = lastResponse?.url == response.url ? lastResponse?.status : nil
        let record = RequestRecord(
            sourceID: source.id, intent: intent, url: response.url, statusCode: status,
            byteCount: response.data.count, parsedCount: count, failure: nil, date: .now
        )
        Task { await RequestLog.shared.record(record, body: response.data) }

        // A first page that parses to nothing means the markup moved, not that the
        // site is empty. Say so rather than showing a blank feed.
        if count == 0 && page == 1 {
            throw ContentError.noResults(source.displayName)
        }
    }

    private func source(with id: String) throws -> any ContentSource {
        guard let source = ContentSources.source(with: id) else {
            throw ContentError.unknownSource(id)
        }
        return source
    }

    private func source(of feed: Feed) throws -> any ContentSource {
        try source(with: feed.sourceID)
    }
}
