/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Reads the renditions a master HLS playlist advertises.
*/

import Foundation

/// Reads the renditions a master HLS playlist advertises.
///
/// A master playlist is a list of alternatives rather than a stream, so playing it
/// directly leaves the choice to the player. Expanding it into one ``StreamSource``
/// per rendition keeps every source behaving the same way: the app picks a height,
/// the Maximum Quality setting means the same thing everywhere, and the interface
/// can say which one it's about to play.
enum HLSManifest {
    /// Returns the renditions a master playlist lists, highest first.
    ///
    /// Returns an empty array for a media playlist — one that lists segments rather
    /// than alternatives — so callers can fall back to playing it as-is.
    static func streams(in text: String, relativeTo base: URL) -> [StreamSource] {
        var streams = [StreamSource]()
        var pendingHeight: Int?

        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("#EXT-X-STREAM-INF") {
                pendingHeight = height(inAttributes: trimmed)
            } else if !trimmed.hasPrefix("#") {
                // The line after a stream tag is that rendition's playlist.
                if let height = pendingHeight, let url = URL(string: trimmed, relativeTo: base)?.absoluteURL {
                    streams.append(StreamSource(url: url, height: height))
                }
                pendingHeight = nil
            }
        }
        return streams.sorted { $0.height > $1.height }
    }

    /// Reads the vertical resolution out of a `RESOLUTION=1920x1080` attribute.
    private static func height(inAttributes line: String) -> Int? {
        guard let range = line.range(of: "RESOLUTION=") else { return nil }
        let value = line[range.upperBound...].prefix { !$0.isWhitespace && $0 != "," }
        guard let separator = value.firstIndex(of: "x") else { return nil }
        return Int(value[value.index(after: separator)...])
    }
}
