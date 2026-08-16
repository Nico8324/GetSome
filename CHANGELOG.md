# Changelog

Notable changes, newest first. Versions follow [semantic versioning](https://semver.org),
though there is no distribution path — a tag marks a state worth returning to
rather than a shipped build.

## 1.0.0

The first tagged release, and the one where the app stopped being a browser for
four sites and became a single catalog assembled from them.

### One catalog instead of four

- **Feeds merge across sites.** A `Feed` now carries a `FeedKind` — the listing
  it *is*, rather than the word its site uses for it — so mat6tube's "Popular",
  Pornhub's "Hot" and the other front pages are one collection. Shelves went from
  twenty-four cards naming publishers to fourteen naming what they contain.
- **A page is gathered, not fetched.** `ContentClient` asks every member site for
  page *n* concurrently and interleaves the answers round-robin, with the site
  chosen on the profile screen leading. A site that fails is dropped; the request
  only fails when every site did.
- **Listings only one site publishes merge too**, with one member. MissAV's
  subtitled feeds and XVideos' Verified are named for their contents like
  everything else, and fill in on their own the day a second site adds the same
  listing.
- **Search and keywords span every site by default**, and a merged feed screen
  offers a site filter for narrowing back down, credited with the sites actually
  behind it.
- **Keywords screen.** Every keyword the app has encountered, ranked by how often
  it appeared, filterable, with the sites that publish each one. Built from what's
  been browsed, because no site publishes an index.

### Watching

- Playback position is remembered and offered as **Continue Watching**.
- **Up Next** proposes the following video, with a countdown at the end.
- A **quality menu** during playback, and one automatic retry that re-resolves the
  stream when one fails mid-play.
- **Scene thumbnails are seek points** — tapping one opens the player at roughly
  that moment. Offsets are inferred by spreading the strip across the running
  time, because no site publishes a timestamp per image.

### Launch, and heat

- Feed snapshots and a poster disk cache mean the first screen is populated at
  launch rather than after the network answers.
- Hero previews play **once** and release their player. Looping them re-downloaded
  the clip every cycle, which a phone reports as heat. Hero rotation is one bounded
  tour, and posters decode through ImageIO at a bounded size.

### Translation

- Titles are translated **on device** when the language is already installed, and
  through Google only otherwise. The app never downloads a language pack.
- **Keywords are no longer translated.** They're search terms of art: machine
  translation turned "fishnet" into fishing equipment, and a site's own search only
  understands the word it published.
- XVideos watch pages now yield their keyword list, which listings there omit.

### Privacy and storage

- Optional **Face ID lock**, and a privacy cover over the app switcher.
- Saved videos **export and import** as a file.

### Interface

- Ten languages, sharing one `Localizable.xcstrings`.
- Higher-resolution posters where a site publishes them, and a poster placeholder
  that doesn't announce failure before a fetch has failed.
- Feed screens sort by length, date or views, and merged ones filter by site.
