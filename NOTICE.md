# Notice

## Origin

GetSome is derived from Apple's **Destination Video** sample code project. The
SwiftUI shell it inherits — tab navigation, hero banner, card layouts, the
`AVPlayerViewController` playback stack, Picture in Picture, SharePlay, and the
visionOS immersive environment — is Apple's work, not this project's.

`LICENSE.txt` is Apple's original sample-code licence and stays in place. It
governs the inherited code, and its copyright notice must be retained in
redistribution. This project is not affiliated with, endorsed by, or supported by
Apple.

What this project added: the multi-source content layer (`Model/Sources`), the
networking and caching client, feed paging, saved videos, translation, the profile
and diagnostics screens, and the per-site implementations.

## Content sources

The app has no catalog of its own. It requests the same pages a browser requests
from third-party sites and reads their published metadata, then streams media from
those sites' own servers using the URLs and tokens they publish.

That has consequences worth stating plainly:

- **It depends on other people's page structure.** A redesign breaks parsing. Each
  site is isolated in one file so a break is a contained fix — see
  [Docs/AddingASource.md](Docs/AddingASource.md).
- **It is subject to those sites' terms.** Whether automated access is permitted is
  between the operator of a build and the site. Nothing here grants that right.
- **No media is redistributed or stored.** Playback streams directly from the
  source site, with its own signed, short-lived URLs. The app caches page text and
  poster images only.

## Boundaries kept during development

These held throughout and are worth keeping:

- Media URLs and tokens are **passed through unmodified**, exactly as each site's
  own player uses them. No signature is forged, extended, or stripped.
- Where a site presents a self-attestation age disclaimer — a checkbox, not a
  verification — the app sends the same cookie a person clicking it would, and only
  after its own age gate has been confirmed.
- **No attempt is made to defeat real age verification** or geographic restriction.
  If a site places identity- or document-based age assurance in front of its
  catalog, the correct outcome is that the source stops working.

## Content

The sites this app browses serve adult material. It shows an age confirmation on
first launch and loads nothing until confirmed. It has no App Store distribution
path — build and run it on your own devices.
