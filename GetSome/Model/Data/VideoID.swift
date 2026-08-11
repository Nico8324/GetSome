/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The identity of a video, which is the site it came from plus that site's own identifier.
*/

import Foundation

/// The identity of a video: the site it came from, plus that site's own identifier.
///
/// This is a pair rather than an encoded string on purpose. Two sites can — and
/// eventually will — use the same identifier for different videos, so neither half
/// identifies a video on its own. Keeping the halves separate means no separator
/// character is load-bearing, no site's identifier format can break parsing, and
/// renaming a source is a change to one stored field instead of a string rewrite.
///
/// ``description`` produces a text form for logs and for the few system interfaces
/// that insist on a string. Nothing parses that form back into an identity.
struct VideoID: Hashable, Sendable, Codable, CustomStringConvertible {
    /// The identifier of the ``ContentSource`` that published the video.
    let sourceID: String

    /// The site's own identifier for the video, such as `-13001002_456239834`.
    let itemID: String

    init(sourceID: String, itemID: String) {
        self.sourceID = sourceID
        self.itemID = itemID
    }

    var description: String {
        "\(sourceID)/\(itemID)"
    }
}

extension VideoID {
    /// The source that published this video, if the app still browses it.
    ///
    /// This is `nil` for a video saved from a site the app no longer ships, which
    /// is why callers treat it as optional rather than assuming it resolves.
    var source: (any ContentSource)? {
        ContentSources.source(with: sourceID)
    }

    /// The page that presents this video on its source site.
    var watchURL: URL? {
        source?.watchURL(forItem: itemID)
    }
}
