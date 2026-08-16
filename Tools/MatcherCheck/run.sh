#!/bin/bash
#
# Checks VideoMatcher against known pairs, without building the app.
#
# The matcher decides whether two sites are publishing the same video, and a
# wrong "yes" hides one of them invisibly — so it wants checking on cases we can
# state the answer to, rather than only on whatever four live sites happen to be
# serving today. Two of them are commonly blocked or region-locked, which makes
# live verification unavailable exactly when it would be most wanted.
#
# The app has no test target, and this follows what Docs/AddingASource.md already
# recommends for parsers: compile the source on its own against a small main and
# run it. Video.swift arrives with the two members that reach into the source
# registry removed, since matching never uses them.
#
# Usage: Tools/MatcherCheck/run.sh

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

python3 - "$root" "$build" <<'PY'
import sys
root, build = sys.argv[1], sys.argv[2]
video = open(f"{root}/GetSome/Model/Data/Video.swift").read()
cuts = [
    ("extension Video {\n    /// Creates a video from a source's own identifier",
     "    /// Creates a placeholder for a video the app can identify but hasn't loaded yet."),
    ("    /// The source this video came from, if the app still browses it.",
     "    /// Returns this video updated with everything `other` actually supplies."),
]
for start, end in cuts:
    if start not in video or end not in video:
        raise SystemExit(
            "Video.swift no longer has the shape this script trims.\n"
            "Update the cut markers in Tools/MatcherCheck/run.sh."
        )
    i, j = video.index(start), video.index(end)
    video = video[:i] + ("extension Video {\n" if start.startswith("extension") else "") + video[j:]
open(f"{build}/Video.swift", "w").write(video)
PY

cp "$root/GetSome/Model/Data/VideoMatcher.swift" "$root/Tools/MatcherCheck/Stubs.swift" "$build/"
# Named main.swift on arrival: top-level statements compile in that file alone.
cp "$root/Tools/MatcherCheck/Cases.swift" "$build/main.swift"

swiftc -O -o "$build/check" \
    "$build/Stubs.swift" "$build/Video.swift" "$build/VideoMatcher.swift" "$build/main.swift"
"$build/check"
