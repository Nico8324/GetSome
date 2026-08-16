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

    /// In-flight GET requests keyed by URL, so identical simultaneous requests
    /// coalesce to a single network call. A second caller awaits the first's task
    /// instead of issuing a duplicate request.
    private var inFlight = [URL: Task<SourceResponse, Error>]()

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

        // Prune the disk cache once at init time, off the current task so it
        // doesn't block startup. Utility priority keeps it out of the way.
        Task.detached(priority: .utility) {
            PosterDiskCache.prune()
        }
    }

    /// Loads a page of videos from the specified feed.
    /// - Parameters:
    ///   - feed: The feed to load. Its source must be one the app knows.
    ///   - page: A one-based page number.
    func videos(for feed: Feed, page: Int = 1) async throws -> [Video] {
        if feed.isMerged {
            return try await mergedVideos(for: feed, page: page)
        }
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
            var videos = try source.videos(inListing: response)

            // A listing that publishes ids alone — the liked-videos list — is resolved
            // a page at a time. Every id costs a request, so the page size is the
            // limit on how many: the whole list would be hundreds.
            if videos.isEmpty {
                let ids = try source.itemIDs(inListing: response)
                if !ids.isEmpty {
                    videos = await resolve(ids: ids, page: page, from: source)
                }
            }
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

    /// Loads the same page from every site that publishes this listing, interleaved.
    ///
    /// Each site paginates on its own, so page *n* of a merged feed is page *n* of
    /// each member — the pages stay aligned however differently the sites number
    /// their results. Sites are fetched concurrently and a failure is tolerated: one
    /// site being down shouldn't empty a shelf the other three could fill. The
    /// request only fails when every site did.
    private func mergedVideos(for feed: Feed, page: Int) async throws -> [Video] {
        let members = ContentSources.members(of: feed)
        guard !members.isEmpty else { throw ContentError.unsupportedFeed(feed.name) }

        let outcomes = await withTaskGroup(of: (Int, Result<[Video], Error>).self) { group in
            for (index, member) in members.enumerated() {
                group.addTask {
                    do {
                        return (index, .success(try await self.videos(for: member, page: page)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var collected = [(Int, Result<[Video], Error>)]()
            for await outcome in group { collected.append(outcome) }
            return collected
        }

        var pages = Array(repeating: [Video](), count: members.count)
        var firstError: Error?
        for (index, outcome) in outcomes {
            switch outcome {
            case .success(let videos): pages[index] = videos
            case .failure(let error): if firstError == nil { firstError = error }
            }
        }

        let interleaved = Self.interleaved(pages)
        if interleaved.isEmpty, let firstError { throw firstError }
        // Sites republish each other, so the same scene arrives two or three times
        // under different titles. Collapsed after interleaving, not before, so the
        // copy that survives is the one from the site that leads the order.
        let merged = VideoMatcher.deduplicated(interleaved)
        note(merged, collapsedFrom: interleaved.count, in: feed.name)
        return merged
    }

    /// Records what a page's deduplication did, to the debug log.
    ///
    /// A merge that shouldn't have happened is invisible in the interface — the
    /// video it hid simply isn't there — so the pairs are worth being able to read
    /// back. Debug level: this is a developer's question, not a diagnostics report.
    private func note(_ merged: [Video], collapsedFrom count: Int, in feedName: String) {
        guard merged.count < count else { return }
        logger.debug("\(feedName, privacy: .public): \(count - merged.count) copies collapsed")
        for video in merged where !video.alternateIDs.isEmpty {
            let others = video.alternateIDs.map(\.sourceID).joined(separator: ", ")
            logger.debug("  ⇄ \(video.name) [\(video.sourceID) + \(others)] \(video.duration)s")
        }
    }

    /// Round-robin, so a gathered page reads as one list rather than several laid
    /// end to end. Callers pass their sources in preference order, which becomes
    /// what a person sees without scrolling.
    private static func interleaved(_ pages: [[Video]]) -> [Video] {
        var result = [Video]()
        let longest = pages.map(\.count).max() ?? 0
        for position in 0..<longest {
            for videos in pages where position < videos.count {
                result.append(videos[position])
            }
        }
        return result
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

    /// Searches every site that can search, interleaved the way a merged feed is.
    ///
    /// A keyword belongs to the site that published it, but the thing it names
    /// doesn't: "fishnet" is a real search term on all four. Asking only the site a
    /// tag came from meant the other three catalogs stayed invisible behind a chip
    /// that looked like it covered everything. Sites that return nothing for a term
    /// they don't use simply contribute nothing.
    func videos(matchingEverywhere query: String, page: Int = 1) async throws -> [Video] {
        let sources = ContentSources.all.filter(\.supportsSearch)
        guard !sources.isEmpty else { return [] }

        let outcomes = await withTaskGroup(of: (Int, Result<[Video], Error>).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    do {
                        return (index, .success(try await self.videos(matching: query, in: source.id, page: page)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var collected = [(Int, Result<[Video], Error>)]()
            for await outcome in group { collected.append(outcome) }
            return collected
        }

        var pages = Array(repeating: [Video](), count: sources.count)
        var firstError: Error?
        for (index, outcome) in outcomes {
            switch outcome {
            case .success(let videos): pages[index] = videos
            case .failure(let error): if firstError == nil { firstError = error }
            }
        }

        let interleaved = Self.interleaved(pages)
        if interleaved.isEmpty, let firstError { throw firstError }
        return VideoMatcher.deduplicated(interleaved)
    }

    /// The most ids to resolve for one page of a listing that publishes ids alone.
    private static let resolvedPageSize = 24

    /// Turns bare item identifiers into videos, one page's worth at a time.
    ///
    /// Each id needs its own watch page, so these run concurrently and the ones that
    /// fail are dropped rather than failing the page: a liked video the site has
    /// since removed is normal, and shouldn't empty the shelf.
    private func resolve(ids: [String], page: Int, from source: any ContentSource) async -> [Video] {
        let start = (page - 1) * Self.resolvedPageSize
        guard start < ids.count else { return [] }
        let slice = Array(ids[start..<min(start + Self.resolvedPageSize, ids.count)])

        return await withTaskGroup(of: (Int, Video?).self) { group in
            for (offset, itemID) in slice.enumerated() {
                group.addTask { [weak self] in
                    guard let self else { return (offset, nil) }
                    return (offset, await self.video(forItemID: itemID, from: source))
                }
            }
            // Reassembled by position: the site's order is the person's order, and a
            // task group finishes in whatever order the network allows.
            var found = [(Int, Video)]()
            for await (offset, video) in group {
                if let video { found.append((offset, video)) }
            }
            return found.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func video(forItemID itemID: String, from source: any ContentSource) async -> Video? {
        do {
            let response = try await fetch(source.watchURL(forItem: itemID), from: source, intent: "resolve")
            return try source.details(inWatchPage: response, itemID: itemID).video
        } catch {
            return nil
        }
    }

    /// Refreshes the playlists a signed-in person keeps, so they can be feeds.
    ///
    /// Separate from ``videos(for:page:)`` because the answer is playlists, not
    /// videos: it feeds the picker rather than a screen. Silent on failure — a
    /// person who isn't signed in simply has none, which isn't an error worth
    /// surfacing anywhere.
    @discardableResult
    func refreshPlaylists(for sourceID: String) async -> [AccountPlaylist] {
        guard let source = ContentSources.source(with: sourceID) as? XVideosSource,
              CredentialStore.hasCredential(for: source.id) else { return [] }
        do {
            let (response, _) = try await SourceAuthenticator.shared.page(
                for: source.playlistIndexRequest, from: source
            )
            let playlists = source.playlists(in: response)
            // Only replace what's remembered when the site actually answered with
            // something. A refused session answers an empty list, and letting that
            // overwrite the cache would make the feeds vanish on a blip.
            if !playlists.isEmpty {
                AccountPlaylistStore.setPlaylists(playlists, for: source.id)
            }
            logger.debug("\(source.displayName, privacy: .public): \(playlists.count) playlist(s)")
            return playlists
        } catch {
            logger.error("Couldn’t list playlists: \(String(describing: error), privacy: .public)")
            return []
        }
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

        // Check the disk cache before making a network request. A hit populates
        // the memory cache so it's available for the lifetime of this session.
        if let diskData = PosterDiskCache.data(for: url) {
            imageCache[url] = diskData
            imageOrder.append(url)
            if imageOrder.count > imageCacheLimit {
                imageCache.removeValue(forKey: imageOrder.removeFirst())
            }
            return diskData
        }

        let request = ContentSources.source(with: sourceID)?.request(for: url) ?? URLRequest(url: url)
        guard let data = try? await session.data(for: request).0, !data.isEmpty else { return nil }

        // Store the fetched image in both caches for quick access in this session
        // and persistence across launches.
        imageCache[url] = data
        imageOrder.append(url)
        if imageOrder.count > imageCacheLimit {
            imageCache.removeValue(forKey: imageOrder.removeFirst())
        }
        PosterDiskCache.store(data, for: url)
        return data
    }

    /// Warms the image cache with poster thumbnails for upcoming videos.
    ///
    /// A grid loads posters as cells appear, so every scroll begins with gray
    /// placeholders. Prefetching the next screenful hides the network latency and
    /// makes scrolling feel immediate. Failures are best-effort and ignored.
    func prefetchPosters(for videos: [Video]) async {
        guard !videos.isEmpty else { return }

        // Collect URLs to prefetch.
        var urlsToFetch: [(URL, String)] = []
        for video in videos {
            if let url = video.thumbnailURL {
                urlsToFetch.append((url, video.sourceID))
            }
        }

        guard !urlsToFetch.isEmpty else { return }

        // Fetch at most 4 concurrent images to avoid overwhelming the network.
        let batchSize = 4
        for batch in stride(from: 0, to: urlsToFetch.count, by: batchSize) {
            let end = min(batch + batchSize, urlsToFetch.count)

            await withTaskGroup(of: Void.self) { group in
                for (url, sourceID) in urlsToFetch[batch..<end] {
                    group.addTask {
                        _ = await self.imageData(at: url, from: sourceID)
                    }
                }
            }
        }
    }

    /// Discards everything the client has cached.
    func clearCache() {
        resolvedDetails.removeAll()
        imageCache.removeAll()
        imageOrder.removeAll()
        PosterDiskCache.removeAll()
    }

    // MARK: - Requests

    /// Fetches a page, coalescing identical concurrent GET requests and retrying
    /// transient failures once.
    ///
    /// For GET requests with no body, a second simultaneous request for the same URL
    /// awaits the first's task instead of issuing a duplicate. For non-GET requests
    /// (which have an httpBody), each request proceeds independently.
    private func fetch(
        _ url: URL,
        from source: any ContentSource,
        intent: String
    ) async throws -> SourceResponse {
        try await pace(source)
        let request = source.request(for: url)

        // Only coalesce GET requests with no body.
        if request.httpBody == nil {
            // Check if a request for this URL is already in flight.
            if let existingTask = inFlight[url] {
                return try await existingTask.value
            }

            // Create and store a task for coalescing.
            let task = Task {
                try await performFetch(url, from: source, intent: intent)
            }
            inFlight[url] = task

            do {
                let result = try await task.value
                inFlight.removeValue(forKey: url)
                return result
            } catch {
                inFlight.removeValue(forKey: url)
                throw error
            }
        } else {
            // Non-GET requests bypass coalescing.
            return try await performFetch(url, from: source, intent: intent)
        }
    }

    /// The last time a request went to each site, and how long to leave it alone.
    private var lastRequest = [String: Date]()
    private var cooldownUntil = [String: Date]()

    /// The gap to leave between two requests to the same site.
    ///
    /// Aggregating changed the shape of this app's traffic. Browsing one site meant
    /// one request per screen; a merged shelf means one *per site*, and several
    /// shelves load at once — so each site now sees a burst where it used to see a
    /// trickle. Sites read bursts as robots, and at least one has started answering
    /// with a challenge page. Spacing requests is both the polite behaviour and the
    /// self-interested one: a site that blocks the app is a site the app can't read.
    private static let minimumInterval: TimeInterval = 0.35

    /// How long to leave a site alone once it has refused.
    private static let cooldown: TimeInterval = 120

    /// Waits out this site's spacing, and refuses outright while it's cooling down.
    private func pace(_ source: any ContentSource) async throws {
        if let until = cooldownUntil[source.id] {
            if until > .now {
                // Failing here rather than asking is the point of a cooldown: a site
                // that just refused will refuse again, and each attempt makes the
                // refusal last longer.
                throw ContentError.blocked(source.displayName)
            }
            cooldownUntil[source.id] = nil
        }

        if let last = lastRequest[source.id] {
            let due = last.addingTimeInterval(Self.minimumInterval)
            if due > .now {
                try? await Task.sleep(for: .seconds(due.timeIntervalSinceNow))
            }
        }
        lastRequest[source.id] = .now
    }

    /// Marks a site as refusing, so the app stops asking for a while.
    private func beginCooldown(for source: any ContentSource, status: Int) {
        cooldownUntil[source.id] = Date().addingTimeInterval(Self.cooldown)
        logger.error("\(source.id, privacy: .public) answered \(status) — resting it for \(Int(Self.cooldown))s")
    }

    /// Performs a fetch with retry for transient failures.
    ///
    /// Retries once on transient network errors (timeout, lost connection, can't
    /// connect) or on HTTP 5xx status codes. A transient hiccup shouldn't kill a
    /// whole feed, but a systematic refusal (4xx) shouldn't be hammered either.
    /// Waits 1.5 seconds between attempts.
    private func performFetch(
        _ url: URL,
        from source: any ContentSource,
        intent: String
    ) async throws -> SourceResponse {
        return try await performFetchWithRetry(url, from: source, intent: intent, attempt: 1)
    }

    private func performFetchWithRetry(
        _ url: URL,
        from source: any ContentSource,
        intent: String,
        attempt: Int
    ) async throws -> SourceResponse {
        let data: Data
        let status: Int?
        let finalURL: URL
        do {
            let (body, response) = try await session.data(for: source.request(for: url))
            data = body
            status = (response as? HTTPURLResponse)?.statusCode
            finalURL = response.url ?? url
        } catch let error as URLError {
            // Check for transient network errors on the first attempt.
            if attempt == 1 && shouldRetry(error) {
                // Log this failed attempt.
                await RequestLog.shared.record(
                    RequestRecord(sourceID: source.id, intent: intent, url: url, statusCode: nil,
                                  byteCount: 0, parsedCount: nil, failure: error.localizedDescription,
                                  date: .now)
                )
                // Wait before retrying.
                try await Task.sleep(nanoseconds: 1_500_000_000)
                return try await performFetchWithRetry(url, from: source, intent: intent, attempt: 2)
            }
            // Not retryable or second attempt failed.
            await RequestLog.shared.record(
                RequestRecord(sourceID: source.id, intent: intent, url: url, statusCode: nil,
                              byteCount: 0, parsedCount: nil, failure: error.localizedDescription,
                              date: .now)
            )
            throw error
        } catch {
            await RequestLog.shared.record(
                RequestRecord(sourceID: source.id, intent: intent, url: url, statusCode: nil,
                              byteCount: 0, parsedCount: nil, failure: error.localizedDescription,
                              date: .now)
            )
            throw error
        }

        // Check for server errors on the first attempt.
        if let status, (500...599).contains(status), attempt == 1 {
            logger.error("Request for \(url.absoluteString, privacy: .public) failed: \(status)")
            // Log this failed attempt.
            await RequestLog.shared.record(
                RequestRecord(sourceID: source.id, intent: intent, url: url, statusCode: status,
                              byteCount: data.count, parsedCount: nil,
                              failure: "transient server error", date: .now)
            )
            // Wait before retrying.
            try await Task.sleep(nanoseconds: 1_500_000_000)
            return try await performFetchWithRetry(url, from: source, intent: intent, attempt: 2)
        }

        if let status, !(200..<300).contains(status) {
            logger.error("Request for \(url.absoluteString, privacy: .public) failed: \(status)")
            // A refusal is about the site, not this request: 403 is a challenge
            // page or a block, 429 is being told to slow down. Either way the next
            // nine requests of a fan-out would get the same answer and dig the hole
            // deeper, so the site gets rested instead.
            if status == 403 || status == 429 {
                beginCooldown(for: source, status: status)
            }
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

    /// Returns whether a URLError is a transient network failure that warrants a retry.
    private func shouldRetry(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost:
            return true
        default:
            return false
        }
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
