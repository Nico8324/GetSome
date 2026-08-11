# GetSome

GetSome is a multiplatform video-browsing app for iOS, iPadOS, macOS, tvOS, and visionOS. It browses several video sites through one interface — feeds, categories, and full-text search — and streams with the system player.

**Sites it ships with**

| Site | Feeds | Categories | Playback |
| --- | --- | --- | --- |
| mat6tube | popular, newest, explore, watching now, 3 charts | — (publishes no index) | progressive MP4 |
| Pornhub | hot, newest, 3 charts | not yet | adaptive HLS |
| XVideos | popular, newest, verified | ~2,000 tags | HLS, 250p–1080p |

The app is built on Apple's *Destination Video* sample. It keeps that project's SwiftUI shell — tab navigation, hero banner, card layouts, `AVPlayerViewController` playback, Picture in Picture, SharePlay, and the visionOS immersive environment — and replaces its bundled sample catalog with live content.

## Architecture

The backend is built around one protocol, so the app can browse several sites at once.

| Concern | Type |
| --- | --- |
| What a site must provide | `Model/Sources/ContentSource.swift` |
| The list of sites the app ships with | `Model/Sources/ContentSources.swift` |
| Shared helpers for sites that publish markup | `Model/Sources/HTMLScanner.swift` |
| The per-site implementations | `Model/Sources/Mat6TubeSource.swift`, `PornhubSource.swift`, `XVideosSource.swift` |
| Shared HLS playlist reading | `Model/Sources/HLSManifest.swift` |
| Recent requests, for reporting a break | `Model/Networking/RequestLog.swift` |
| Requests, caching, stream selection | `Model/Networking/ContentClient.swift` |
| Feed paging and state for views | `Model/FeedStore.swift` |

`ContentClient` knows how to make a request and cache a result; it holds no knowledge of any particular site. Everything site-specific lives behind `ContentSource`.

### Adding a site

Write one conformance and add it to `ContentSources.all`. Nothing above that layer changes. See [Docs/AddingASource.md](Docs/AddingASource.md) for the skeleton, the reconnaissance checklist, and the pitfalls.

```swift
struct ExampleSource: ContentSource {
    let id = "example"                    // stable — it appears in saved data
    let displayName = "Example"
    let homeURL = URL(string: "https://example.com/")!

    var feeds: [Feed] {
        [makeFeed("trending", name: "Trending", description: "…", icon: "flame"),
         makeFeed("top", name: "Top", description: "…", icon: "crown", group: .chart)]
    }

    func listingURL(for feed: Feed, page: Int) -> URL? { … }
    func searchURL(query: String, page: Int) -> URL? { … }
    func watchURL(forItem itemID: String) -> URL { … }
    func videos(inListing response: SourceResponse) throws -> [Video] { … }
    func details(inWatchPage response: SourceResponse, itemID: String) throws -> VideoDetails { … }
}
```

Defaults cover the rest: a browser-shaped `URLRequest`, resolution selection per platform, and which feed the Watch Now screen leads with. A source receives raw `Data`, so a JSON API is as easy to wrap as a page of markup — `HTMLScanner` is only there for the latter.

The interface adapts on its own: with several sources, Browse and Search grow a site picker, feed names get qualified with their site, and the detail screen names where a video came from.

### Video identity

A video is identified by a **pair** — the site it came from and that site's own identifier — modeled as `VideoID` (`Model/Data/VideoID.swift`), never as an encoded string:

```swift
struct VideoID: Hashable, Sendable, Codable {
    let sourceID: String
    let itemID: String
}
```

Two sites can, and eventually will, use the same identifier for different videos, so neither half identifies a video alone. Keeping the halves separate means no separator character is load-bearing — a site whose ids contain `/`, `|`, or spaces can't break parsing — and `description` (`mat6tube/-13001002_456239834`) exists only for logs and for system interfaces that demand a string. Nothing parses it back.

`SavedVideo` stores the two fields and enforces `#Unique<SavedVideo>([\.sourceID, \.itemID])`. Renaming a source becomes an update to one column rather than a string rewrite.

Three consequences worth knowing:

- **Normalize ids at the source.** `normalizedItemID(_:)` collapses the variants a site hands out — trailing slashes, tracking queries, fragments — so one video can't be saved twice. Override it if your site needs more.
- **Renames are survivable.** List an old identifier in `previousIDs` and the registry keeps resolving it, so nothing a person saved is stranded.
- **Dropping a source doesn't corrupt anything.** `Video.source` is optional and `isAvailable` is false; such videos stay in the library, marked, with playback disabled.

### Categories

A category is just a ``Feed`` discovered at runtime rather than declared in code, so the store, the feed screen, and paging treat it exactly like a built-in feed. A source opts in by overriding `categoriesURL()` and `categories(in:)`; one that publishes no index overrides nothing and the app simply offers none for it.

Because a site can publish thousands, categories are excluded from sidebar tab generation — see `FeedGroup.navigableGroups`.

### Resolving playback

Most sites publish their media URL on the watch page. Some don't: xvideos serves only a 360p MP4 inline and returns the real set from an RPC its own player calls. `streamsURL(forItem:)` and `streams(in:)` cover that second request, and `ContentClient` expands any master HLS playlist into one source per rendition — so every site ends up with comparable heights, the Maximum Quality setting means the same thing everywhere, and the app can report what it is playing.

## How mat6tube content is read

That site doesn't publish an API, so its source requests the same pages a browser requests and reads the metadata out of the markup. Listing pages yield a title, poster, duration, view count, and HD flag per video. A watch page yields playback sources, upload date, keywords, and related videos. The site signs its media URLs with a short expiration, so the app resolves a stream at the moment of playback rather than storing one.

Because this depends on the site's page structure, a redesign there breaks parsing — and `Mat6TubeSource` is the only file that needs fixing.

## Translation

Sites publish titles and keywords in whatever language a video was uploaded in. `Model/TranslationStore.swift` translates them into the device's language with Apple's Translation framework — on device, nothing sent anywhere.

- Views call `translator.text(for:)`, which answers immediately with the original and queues a miss. The queue is `@ObservationIgnored`, so queueing from inside a view's body doesn't invalidate the view that's drawing.
- Misses are grouped by detected language (`NLLanguageRecognizer`, weighted by a prior — without one it reads Russian titles as Kazakh with full confidence, and nothing ever matches an installed pair).
- A batch builds its own `TranslationSession(installedSource:target:)` inside one `nonisolated` function. The session and its `Request` aren't `Sendable`, so both are created and consumed there; only strings come back.
- Results land in one write per batch, so a page of cards redraws once rather than once per title, and persist to Application Support, capped.

### Why one `translationTask` remains

A directly built session reports `canRequestDownloads == false` and throws `notInstalled` for a language the device doesn't have — it can translate, but it can't ask for a download. Only a session vended by SwiftUI's `translationTask` can present the system download UI. So `ContentView` hosts exactly one such task, used for nothing but that prompt.

Its closure is `@Sendable` so it doesn't inherit the view's main-actor isolation, which would make the non-`Sendable` session a "sending" error.

### Downloads

A language must be downloaded before it can be translated, and only a person can approve that — the framework offers no way to fetch one silently, and no way to reach Apple's server-side translation (the path Safari uses). The app asks once per language, at the moment it first meets one, and remembers what it already asked about. The profile screen can re-ask.

Translated: video titles, keywords on cards and detail pages, and keyword chips. A keyword chip still *searches* with the original word, since a site only knows its own vocabulary. The detail screen also offers the system translation popover (`translationPresentation`) for the full untrimmed title.

## Profile and settings

`Views/ProfileView.swift` is reached from the profile button — a toolbar item on iOS and macOS, the expanding hover button over Watch Now on visionOS, and a tab on tvOS, which has no navigation bar to hold a button. There are no accounts; the screen exists to show what the app has accumulated on the device and to change how it behaves:

- **Sites** — which source Watch Now leads with (`ContentSources.primarySourceKey`)
- **Maximum Quality** — the resolution ceiling for stream selection (`Model/PlaybackSettings.swift`), read by `ContentSource.preferredStream(from:)`
- **Storage** — saved-video count, remove all, clear the resolved-stream cache
- **Content** — lock the app, which restores the age gate
- **About** — version, and a link to each source's site

Both preferences live in user defaults rather than an observable object, so `preferredStream(from:)` can consult them while running off the main actor.

## Saved videos

SwiftData stores the videos a person saves (`Model/Data/SavedVideo.swift`). Each saved item holds its own copy of the card metadata plus its source, so the Saved tab works without refetching a listing page.

## Requirements

iOS 26, macOS 26, tvOS 26, or visionOS 26. The Translation framework is unavailable on tvOS and visionOS, so those two build without it and show site text as published.

**Translation can only be tested on real hardware.** The Simulator refuses outright — "Translation is not supported on simulated devices" — so `LanguageAvailability` reports pairs as `supported` but never `installed`, no download prompt appears, and nothing translates. That's the Simulator, not the app. Any failure now surfaces in the profile screen's Language section rather than failing silently.

## Content

The sites this app browses serve adult content. It shows an age confirmation on first launch and loads nothing until a person confirms. It has no App Store distribution path — build and run it on your own devices.
