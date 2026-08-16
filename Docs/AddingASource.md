# Adding a site

Two parts, and they are not equally hard.

**The wiring is a template.** Copy the skeleton below, fill in eight members, add one line to `ContentSources.all`. Nothing above that layer changes — not the client, the feed store, the player, or any view.

**The parsing is reverse engineering.** No template can tell you where a particular site hides its stream URL. Expect that to be most of the work.

---

## 1. Reconnaissance, before writing any Swift

Do this in a browser with the network inspector open. Answer these six questions and the Swift writes itself:

| Question | What you're looking for | mat6tube's answer |
| --- | --- | --- |
| How do listings page? | A query param, a path segment, or a cursor | `?p=2` |
| What listings exist? | Popular / newest / ranked-by-window | `/recent`, `?range=day\|week\|month\|explore`, `/now` |
| How does search work? | Query param or path | `/video/<terms+with+plus>` |
| What identifies a video? | The stable part of its URL | `-13001002_456239834` from `/watch/<id>` |
| Where is the stream? | A `<video>` tag, a JSON blob, or an XHR | `window.playlist = {…}` in the watch page |
| Do media URLs expire? | A `secure=`/`token=`/`expires=` param | Yes — signed, so resolve at playback |

Two things worth checking early, because they change the design:

- **Does a plain `curl` get the same HTML as the browser?** If not, the site is gating on headers. The default `request(for:)` already sends a Safari user agent, language, and referer — that's usually enough. If it needs cookies or a CSRF token, you'll have to override `request(for:)`.
- **Is there a JSON endpoint behind the page?** Sites with an app or infinite scroll often have one. It'll be far more stable than markup. `videos(inListing:)` receives raw `Data`, so a JSON source is no harder than an HTML one — `HTMLScanner` is only there for the scraping case.

## 2. The skeleton

```swift
import Foundation

struct ExampleSource: ContentSource {
    let id = "example"                       // stable forever — it lands in saved data
    let displayName = "Example"
    let homeURL = URL(string: "https://example.com/")!

    var feeds: [Feed] {
        [
            // `kind` is what makes a listing merge with the other sites' version
            // of it. Name and icon come from the kind once merged, so they only
            // show for a listing that has none.
            makeFeed("trending",
                     name: String(localized: "Trending", comment: "Collection name"),
                     description: String(localized: "…", comment: "…"),
                     icon: "flame",
                     kind: .popular),
            makeFeed("top",
                     name: String(localized: "Top", comment: "Collection name"),
                     description: String(localized: "…", comment: "…"),
                     icon: "crown",
                     group: .chart,
                     kind: .topRated)
        ]
    }

    func listingURL(for feed: Feed, page: Int) -> URL? {
        guard feed.sourceID == id else { return nil }
        var components = URLComponents(url: homeURL.appending(path: feed.slug),
                                       resolvingAgainstBaseURL: false)!
        if page > 1 {
            components.queryItems = [URLQueryItem(name: "page", value: String(page))]
        }
        return components.url
    }

    func watchURL(forItem itemID: String) -> URL {
        homeURL.appending(path: "watch/\(itemID)")
    }

    func videos(inListing response: SourceResponse) throws -> [Video] {
        // response.data for JSON, response.text for markup.
        []
    }

    func details(inWatchPage response: SourceResponse, itemID: String) throws -> VideoDetails {
        VideoDetails(sources: [], related: [], video: nil)
    }
}
```

Then one line in `ContentSources.all`:

```swift
static let all: [any ContentSource] = [
    Mat6TubeSource(),
    ExampleSource()
]
```

That's the whole integration. The interface adapts on its own: the site joins every merged collection whose `FeedKind` it publishes, Browse and Search grow a site picker, and the detail screen names where a video came from.

### Tagging listings with a kind

The shelves are built from `FeedKind`, not from sites, so a listing's kind is what
decides whether it joins an existing collection or becomes a new card of its own:

| Your listing | Give it |
| --- | --- |
| A front page / what's hot | `.popular` |
| Newest first | `.latest` |
| Ranked over a day, week or month | `.topDay`, `.topWeek`, `.topMonth` |
| Best rated | `.topRated` |
| Something the app already knows | the matching case — check `FeedKind` first |
| Something genuinely new | a new case, with a name, icon and group |
| Something one-off and account-shaped | leave `kind` nil — it stays reachable in Browse |

A kind with one member is normal and needs no special handling. Add a new case
only when no existing one means the same thing: two cases for one idea is exactly
the duplication the merge exists to remove.

## 3. What you get for free

Override any of these only if the site disagrees with the default:

| Member | Default |
| --- | --- |
| `request(for:)` | Browser user agent, `Accept-Language`, referer |
| `searchURL(query:page:)` | `nil` — the site is treated as unsearchable |
| `supportsSearch` | `true` |
| `preferredStream(from:)` | Honours the person's Maximum Quality setting |
| `normalizedItemID(_:)` | Trims whitespace and slashes |
| `featuredFeed` / `latestFeed` | First and second `.collection` feed |
| `previousIDs` | `[]` |

## 4. Getting it right

- **Give every listing a `kind` you can.** A listing left untagged never reaches the
  shelves — it's only browsable per-site — which is right for an account feed and
  wrong for a front page.
- **`id` is permanent.** It's half of every `VideoID` and is stored with every saved video. Name the service, not the domain — domains move. If you must change it, put the old value in `previousIDs` and the registry keeps resolving it.
- **Normalize item ids.** If the site links the same video as `/watch/abc`, `/watch/abc/`, and `/watch/abc?utm=x`, override `normalizedItemID(_:)` or it gets saved three times.
- **Don't trust one page.** Parse a listing, a search result, and a watch page. Listing markup and related-video markup often differ — on mat6tube one uses `data-src` for the poster and the other uses `src`.
- **Test the parser offline.** Save a page with `curl`, then compile the source against a small `main.swift` and run it. Far faster than rebuilding the app, and it's how every parsing bug in `Mat6TubeSource` was found.

## 5. Roughly how long

For a site that server-renders its listings and puts the stream in a JSON blob: an afternoon, most of it in the browser inspector. Add time if the site paginates by cursor, requires cookies, obfuscates the stream URL, or renders listings client-side — in that last case check for the JSON endpoint the page itself is calling, because scraping a client-rendered page from `URLSession` won't work at all.
