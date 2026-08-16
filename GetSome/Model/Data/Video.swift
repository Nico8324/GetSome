/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A model type that defines the properties of a video.
*/

import Foundation

/// A model type that defines the properties of a video.
///
/// A video belongs to the source it came from — see ``VideoID`` — so videos stay
/// distinct once the app browses more than one site, in saved data and navigation
/// paths alike.
///
/// The app builds these values from listing pages, so every property beyond the
/// identity is best effort: a listing that omits a duration or a view count still
/// produces a usable video.
struct Video: Identifiable, Hashable, Sendable, Codable {
    /// The site this video came from and that site's identifier for it.
    let id: VideoID

    /// The title as the source publishes it, including any trailing keyword list.
    var rawTitle: String

    /// The poster image for the video.
    var thumbnailURL: URL?

    /// A short, silent clip that the source uses for hover previews.
    var previewURL: URL?

    /// The length of the video, in seconds, or `0` when the source doesn't publish one.
    var duration: Int

    /// The view count, formatted by the source, such as `889.7K`.
    var views: String

    /// A Boolean value that indicates whether the source marks the video as high definition.
    var isHD: Bool

    /// The keywords the source associates with the video.
    var tags: [String]

    /// The date the video was uploaded, when the app knows it.
    var uploadDate: Date?

    /// The identifier of the ``ContentSource`` this video came from.
    var sourceID: String { id.sourceID }

    /// The source's own identifier for the video.
    var itemID: String { id.itemID }

    init(
        id: VideoID,
        rawTitle: String,
        thumbnailURL: URL? = nil,
        previewURL: URL? = nil,
        duration: Int = 0,
        views: String = "",
        isHD: Bool = false,
        tags: [String] = [],
        uploadDate: Date? = nil
    ) {
        self.id = id
        self.rawTitle = rawTitle
        self.thumbnailURL = thumbnailURL
        self.previewURL = previewURL
        self.duration = duration
        self.views = views
        self.isHD = isHD
        self.tags = tags
        self.uploadDate = uploadDate
    }
}

extension Video {
    /// Creates a video from a source's own identifier, normalizing it the way that
    /// source expects so the same video can't arrive under two identities.
    init(sourceID: String, itemID: String, rawTitle: String, thumbnailURL: URL? = nil,
         previewURL: URL? = nil, duration: Int = 0, views: String = "", isHD: Bool = false,
         tags: [String] = [], uploadDate: Date? = nil) {
        let normalized = ContentSources.source(with: sourceID)?.normalizedItemID(itemID) ?? itemID
        self.init(id: VideoID(sourceID: sourceID, itemID: normalized), rawTitle: rawTitle,
                  thumbnailURL: thumbnailURL, previewURL: previewURL, duration: duration,
                  views: views, isHD: isHD, tags: tags, uploadDate: uploadDate)
    }

    /// Creates a placeholder for a video the app can identify but hasn't loaded yet.
    init(id: VideoID) {
        self.init(id: id, rawTitle: "")
    }

    /// The source this video came from, if the app still browses it.
    var source: (any ContentSource)? {
        id.source
    }

    /// A Boolean value that indicates whether the app can still play this video.
    ///
    /// This is `false` for a video saved from a site the app no longer ships.
    var isAvailable: Bool {
        source != nil
    }

    /// The page that presents this video on its source site.
    var watchURL: URL? {
        id.watchURL
    }

    /// Returns this video updated with everything `other` actually supplies.
    ///
    /// A detail page usually knows more than a listing — an upload date, a full
    /// keyword list — but not always: some sites publish a view count on the
    /// listing and nowhere else. Merging keeps whichever half has the value.
    func merging(_ other: Video) -> Video {
        guard other.id == id else { return self }
        var result = self
        if !other.rawTitle.isEmpty { result.rawTitle = other.rawTitle }
        if let url = other.thumbnailURL { result.thumbnailURL = url }
        if let url = other.previewURL { result.previewURL = url }
        if other.duration > 0 { result.duration = other.duration }
        if !other.views.isEmpty { result.views = other.views }
        if other.isHD { result.isHD = true }
        if !other.tags.isEmpty { result.tags = other.tags }
        if let date = other.uploadDate { result.uploadDate = date }
        return result
    }

    /// The title with its trailing keyword list removed.
    var name: String {
        let split = TitleFormatter.split(rawTitle)
        return split.title.isEmpty ? rawTitle : split.title
    }

    /// The keywords the source publishes for the video, including those buried in its title.
    var keywords: [String] {
        let fromTitle = TitleFormatter.split(rawTitle).keywords
        var seen = Set<String>()
        return (tags + fromTitle).filter { seen.insert($0.lowercased()).inserted }
    }

    /// A sentence describing the video, assembled from its keywords.
    var synopsis: String {
        let keywords = keywords
        guard !keywords.isEmpty else { return name }
        return keywords.joined(separator: " · ")
    }

    var formattedDuration: String {
        guard duration > 0 else { return "--:--" }
        return Duration.seconds(duration)
            .formatted(.time(pattern: duration >= 3600 ? .hourMinuteSecond : .minuteSecond(padMinuteToLength: 2)))
    }

    /// The view count, or an em dash when the source doesn't publish one.
    var formattedViews: String {
        views.isEmpty ? "—" : String(localized: "\(views) views", comment: "A formatted view count, such as 889.7K")
    }

    var formattedUploadDate: String {
        guard let uploadDate else { return "" }
        return uploadDate.formatted(.dateTime.year())
    }

    /// A short line of metadata for the card and detail views.
    var subtitle: String {
        [formattedDuration, formattedViews, isHD ? "HD" : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
    }
}

/// A type that separates a site title from the keyword list the site appends to it.
enum TitleFormatter {
    /// The result of separating a raw title into its parts.
    struct Split {
        var title: String
        var keywords: [String]
    }

    /// Splits a raw site title into a readable title and a list of keywords.
    ///
    /// Titles on tube sites typically end in a bracketed or comma-separated keyword
    /// list, for example `Some title [porn,teen,anal]`. This method returns the
    /// leading text as the title and the remainder as keywords.
    static func split(_ rawTitle: String) -> Split {
        var working = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        var keywords = [String]()

        // Pull out any bracketed keyword lists.
        while let open = working.lastIndex(of: "["),
              let close = working[open...].firstIndex(of: "]") {
            let inner = working[working.index(after: open)..<close]
            keywords.insert(contentsOf: components(of: String(inner)), at: 0)
            working.removeSubrange(open...close)
            working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Some titles separate their keywords with pipes instead.
        if working.contains("|") {
            let parts = working.split(separator: "|").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let first = parts.first {
                working = first
                keywords.insert(contentsOf: parts.dropFirst().filter { !$0.isEmpty }, at: 0)
            }
        }

        // What remains often ends in a run of comma-separated keywords.
        let parts = working.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if parts.count > 2 {
            working = parts[0]
            keywords.insert(contentsOf: parts.dropFirst().filter { !$0.isEmpty }, at: 0)
        }

        // Strip any trailing run of unmistakably junk keywords. A fixed lexicon avoids
        // the hard problem of distinguishing a tag from the last word of a real title;
        // a wrong guess ruins a title, so only words we're certain are tags qualify.
        let junkKeywords: Set<String> = [
            "porn", "porno", "sex", "xxx", "teen", "milf", "anal", "amateur",
            "hd", "4k", "av", "mp4", "video", "videos", "young", "hot",
            "fuck", "fucking", "hardcore", "creampie", "blowjob", "asian",
            "japanese", "uncensored", "full", "movie", "clip"
        ]
        let tokens = working.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var trailingJunkCount = 0
        for token in tokens.reversed() {
            let normalized = token.lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:-–—\"'"))
            if junkKeywords.contains(normalized) {
                trailingJunkCount += 1
            } else {
                break
            }
        }
        // Only strip if we found at least 2 junk tokens and at least 3 non-junk tokens remain.
        if trailingJunkCount >= 2 && tokens.count - trailingJunkCount >= 3 {
            let stripped = tokens.suffix(trailingJunkCount)
            keywords.insert(contentsOf: stripped, at: 0)
            working = tokens.dropLast(trailingJunkCount).joined(separator: " ")
        }

        let title = working
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,-–—|"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var seen = Set<String>()
        let unique = keywords.filter {
            isTagLike($0) && seen.insert($0.lowercased()).inserted
        }
        return Split(title: title, keywords: Array(unique.prefix(12)))
    }

    /// Whether a string is short enough to read as a tag rather than a sentence.
    ///
    /// Sites sometimes cram an entire phrase between one pair of brackets. Left in,
    /// it becomes a chip far wider than the card it sits on.
    private static func isTagLike(_ keyword: String) -> Bool {
        guard !keyword.isEmpty, keyword.count <= 24 else { return false }
        return keyword.split(whereSeparator: \.isWhitespace).count <= 3
    }

    private static func components(of list: String) -> [String] {
        list.split(whereSeparator: { $0 == "," || $0 == "|" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
