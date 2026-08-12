# Working on GetSome

## Build

Open `GetSome.xcodeproj` and run the **GetSome** scheme. It targets iOS 26,
macOS 26, tvOS 26, and visionOS 26.

Before pushing anything that touches shared code, build all four — the platform
differences are real, and three of the bugs in this project's history were caught
only because one platform failed:

```bash
for d in "generic/platform=iOS Simulator" "platform=macOS" \
         "generic/platform=tvOS Simulator" "generic/platform=visionOS Simulator"; do
  xcodebuild -project GetSome.xcodeproj -scheme GetSome -destination "$d" \
             build CODE_SIGNING_ALLOWED=NO | tail -1
done
```

Things that differ by platform, from experience:

- **tvOS** has no navigation bar for toolbar items, and no `ShareLink`.
- **macOS** wants `.menu` pickers where the others want `.navigationLink`.

## Testing a parser without the app

The fastest loop by a wide margin, and how essentially every parsing bug here was
found. Save a page, then compile the source against a small `main.swift`:

```bash
curl -sL -A "Mozilla/5.0 … Safari/605.1.15" "https://example.com/listing" -o page.html
swiftc -swift-version 6 -o test main.swift empty.swift \
  GetSome/Model/Sources/*.swift GetSome/Model/Data/*.swift \
  GetSome/Model/PlaybackSettings.swift && ./test
```

`SourceResponse(url:data:)` takes bytes, so a saved page replays through the real
parser with no network and no app build. (`empty.swift` can be a comment — it just
keeps `swiftc` out of single-file script mode.)

> [!WARNING]
> **Don't judge a site by `curl`.** Cloudflare and similar edges fingerprint the TLS
> handshake, not just the user agent, so `curl` can get a `403` with
> `cf-mitigated: challenge` on a site that serves `URLSession` a clean `200`. missav
> does exactly this — it was written off as unreachable on `curl` evidence before a
> ten-line `URLSession` probe showed the site had been answering all along.
>
> When `curl` is blocked, re-test with the stack the app actually uses before
> concluding anything:
>
> ```swift
> var request = URLRequest(url: url)
> request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
> URLSession.shared.dataTask(with: request) { data, response, _ in … }.resume()
> ```
>
> This cuts the other way too: a site that serves `curl` happily may still refuse
> the app. The only client whose verdict counts is `URLSession`.

## When a site breaks

Expect this; the app depends on other people's markup. A break usually looks like
an empty feed rather than an error, so the app names it: a first page that parses
to zero videos throws `ContentError.noResults` instead of showing nothing.

**Profile › Diagnostics** records the last 40 requests — source, intent, HTTP
status, byte count, parsed count — and keeps the body of the last page that parsed
to nothing. "Prepare Report" writes it to a file that can be shared. The parsed
count is the health signal:

| | meaning |
| --- | --- |
| `HTTP 200 · 475 ko · 24 parsed` | healthy |
| `HTTP 200 · 475 ko · 0 parsed` | markup drift — fix the parser |
| `HTTP 403 · 0 parsed` | blocked, or missing a header the site expects |

## Adding a site

See [Docs/AddingASource.md](Docs/AddingASource.md). Short version: one file, one
line in `ContentSources.all`, nothing above that layer changes. The reconnaissance
is the real work, not the Swift.

Look for a site that **serves its own media, renders listings server-side, and
publishes its media URL unscrambled**. Candidates failing any of the three turned
out to be projects rather than afternoons.

## House style

The inherited Apple code sets the tone; match it.

- Comments explain *why*, not what. Prefer noting the non-obvious constraint —
  which platform disagrees, which assumption proved false — over narrating code.
- Document the surprising thing. Several comments here exist purely because the
  next person would otherwise repeat a wrong assumption.
- Keep site-specific knowledge inside that site's source file. `HTMLScanner`,
  `HLSManifest`, and `ContentClient` must stay site-agnostic.

## Boundaries

Read the "Boundaries kept during development" section of [NOTICE.md](NOTICE.md)
before working on playback. Pass tokens through; don't forge them, and don't work
around real age verification.
