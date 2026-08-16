/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Recognizes the same video published by more than one site.
*/

import Foundation

/// Recognizes the same video published by more than one site.
///
/// Sites republish each other constantly, so a merged feed shows the same scene
/// two or three times under titles nobody wrote the same way. Nothing links those
/// copies: each site issues its own identifier, and there's no shared key to join
/// on. What there is, on every listing, is a title and a running time.
///
/// The rules here are deliberately conservative, because the two mistakes are not
/// equally bad. Missing a duplicate leaves the feed as it is today. Merging two
/// different videos *hides one of them*, and does it invisibly — so every rule
/// requires agreement on running time, and a match is never made on a title alone.
enum VideoMatcher {

    /// How far apart two running times may be and still be the same video.
    ///
    /// Sites round differently and some trim a frame of leader, but nobody is out
    /// by much: a few seconds absolute, and a little more on a long film where the
    /// rounding compounds.
    private static func durationTolerance(for seconds: Int) -> Int {
        max(3, seconds / 50)
    }

    /// The fewest title words a comparison needs before it means anything.
    ///
    /// Generic titles are the trap here — a site that captions three unrelated
    /// clips "Porn" would collapse all three on a duration coincidence. Below this
    /// many distinguishing words, no similarity score is trusted.
    private static let minimumTokens = 3

    /// How alike two titles must be, as a Sørensen–Dice coefficient over their words.
    private static let similarityThreshold = 0.6

    /// Words that identify nothing, so they neither help nor hurt a comparison.
    ///
    /// The junk lexicon that ``TitleFormatter`` strips from the *end* of a title
    /// appears mid-title too, and every site sprinkles it differently — one writes
    /// "hot milf anal", the next writes "anal milf". Dropping them compares what's
    /// left, which is the part that actually names the video.
    /// A title made only of these has nothing to compare: sites caption uploads
    /// with a bare tag list constantly, and two such captions matching is a
    /// coincidence of vocabulary rather than evidence of the same video.
    private static let ignoredWords: Set<String> = TitleFormatter.junkKeywords.union([
        "the", "a", "an", "and", "or", "of", "in", "on", "at", "to", "for", "with",
        "my", "her", "his", "their", "this", "that", "is", "was", "get", "gets",
        "scene", "free", "new", "part", "sexy", "big", "little"
    ])

    /// The comparable form of a video: what it's called, and how long it runs.
    struct Signature {
        /// A studio catalogue number such as `MXGS-1440`, when the title carries one.
        ///
        /// Where both titles have one this is the whole answer. These are issued by
        /// the studio rather than by any site, which makes them the one genuinely
        /// shared key across catalogues — exactly what identity here otherwise lacks.
        let code: String?
        /// The distinguishing words of the title, deduplicated.
        let words: Set<String>
        let duration: Int

        var isComparable: Bool {
            code != nil || (duration > 0 && words.count >= minimumTokens)
        }
    }

    /// A studio catalogue number: two to six letters, a separator, then digits.
    private static let codeExpression = try? NSRegularExpression(
        pattern: #"\b([A-Za-z]{2,6})[-_ ]?(\d{2,5})\b"#
    )

    static func signature(of video: Video) -> Signature {
        let title = video.name
        return Signature(code: code(in: title), words: words(in: title), duration: video.duration)
    }

    private static func code(in title: String) -> String? {
        guard let codeExpression else { return nil }
        let range = NSRange(title.startIndex..., in: title)
        guard let match = codeExpression.firstMatch(in: title, range: range),
              let letters = Range(match.range(at: 1), in: title),
              let digits = Range(match.range(at: 2), in: title) else { return nil }
        // Normalized to LETTERS-DIGITS so `MXGS-1440`, `mxgs1440` and `MXGS 1440`
        // are one code. Leading zeros are kept: they're part of the number.
        return "\(title[letters].uppercased())-\(title[digits])"
    }

    private static func words(in title: String) -> Set<String> {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                   locale: Locale(identifier: "en_US_POSIX"))
        let separators = CharacterSet.alphanumerics.inverted
        return Set(
            folded.components(separatedBy: separators)
                .filter { $0.count > 2 && !ignoredWords.contains($0) }
        )
    }

    /// Whether two videos from different sites are the same video.
    static func isSameVideo(_ first: Video, _ second: Video) -> Bool {
        // Never within one site. A site's own listing is authoritative about what
        // it publishes, and two entries there are two videos by definition.
        guard first.sourceID != second.sourceID else { return false }

        let a = signature(of: first)
        let b = signature(of: second)
        guard a.isComparable, b.isComparable else { return false }

        // A shared catalogue number settles it, provided the running times don't
        // flatly contradict each other — a trailer and its feature can carry the
        // same code, and they are not the same thing to watch.
        if let codeA = a.code, let codeB = b.code, codeA == codeB {
            guard a.duration > 0, b.duration > 0 else { return true }
            return abs(a.duration - b.duration) <= durationTolerance(for: max(a.duration, b.duration))
        }

        guard a.duration > 0, b.duration > 0,
              abs(a.duration - b.duration) <= durationTolerance(for: max(a.duration, b.duration)),
              a.words.count >= minimumTokens, b.words.count >= minimumTokens else {
            return false
        }
        return dice(a.words, b.words) >= similarityThreshold
    }

    /// The Sørensen–Dice coefficient of two word sets: shared words, doubled, over
    /// the total. Chosen over Jaccard because it's steadier when one site's title
    /// is much longer than the other's, which is the usual shape of the problem.
    private static func dice(_ a: Set<String>, _ b: Set<String>) -> Double {
        let shared = a.intersection(b).count
        guard shared > 0 else { return 0 }
        return 2 * Double(shared) / Double(a.count + b.count)
    }

    /// Collapses re-publications of one video into a single entry.
    ///
    /// Order decides which copy survives, so callers should pass videos in the order
    /// they want them preferred — the merged feeds put the person's chosen site
    /// first. A survivor keeps its own identity and takes anything the copies knew
    /// that it didn't, since sites are patchy in different places: one publishes a
    /// view count, another a duration, another the keywords.
    static func deduplicated(_ videos: [Video]) -> [Video] {
        var kept = [Video]()
        // Grouped by duration so each candidate is compared against the handful of
        // videos that could possibly match rather than against everything kept.
        // Feeds run to hundreds of videos and this is on the path of every page.
        var byDuration = [Int: [Int]]()

        for video in videos {
            let bucket = video.duration / 10
            var matchIndex: Int?
            // Adjacent buckets too: a tolerance of a few seconds straddles them.
            for neighbour in (bucket - 1)...(bucket + 1) {
                for index in byDuration[neighbour] ?? [] where isSameVideo(kept[index], video) {
                    matchIndex = index
                    break
                }
                if matchIndex != nil { break }
            }

            if let matchIndex {
                kept[matchIndex] = kept[matchIndex].absorbing(video)
            } else {
                byDuration[bucket, default: []].append(kept.count)
                kept.append(video)
            }
        }
        return kept
    }
}

extension Video {
    /// Returns this video having taken on a copy of itself found on another site.
    ///
    /// The copy's identity is remembered rather than discarded: a stream that
    /// expires or a site that blocks playback can be answered by asking the other
    /// site for the same video. See ``alternateIDs``.
    func absorbing(_ other: Video) -> Video {
        var result = self
        // `merging` refuses across identities, by design — it exists to fold a
        // detail page into its own listing. This is the other case: two identities
        // for one video, where filling gaps is exactly what's wanted.
        if rawTitle.isEmpty { result.rawTitle = other.rawTitle }
        if thumbnailURL == nil { result.thumbnailURL = other.thumbnailURL }
        if previewURL == nil { result.previewURL = other.previewURL }
        if duration == 0 { result.duration = other.duration }
        if views.isEmpty { result.views = other.views }
        if other.isHD { result.isHD = true }
        if uploadDate == nil { result.uploadDate = other.uploadDate }
        // Keywords accumulate: each site tags with its own vocabulary, and the
        // union is a better description of the video than either site's half.
        var seen = Set(tags.map { $0.lowercased() })
        result.tags = tags + other.tags.filter { seen.insert($0.lowercased()).inserted }

        result.alternateIDs = (alternateIDs + [other.id] + other.alternateIDs)
            .filter { $0 != id }
        return result
    }
}
