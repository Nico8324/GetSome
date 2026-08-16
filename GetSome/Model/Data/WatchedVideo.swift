/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A model class that records a video a person watched.
*/

import Foundation
import SwiftData

/// A model class that records a video a person watched.
///
/// Kept by the app rather than read from a site. The sites the app browses either
/// don't record history against an account at all — xvideos keys it to a cookie —
/// or wouldn't share it across the others. A local record works for every source,
/// needs no sign-in, and doesn't disappear when a site changes its mind.
///
/// Identity matches ``SavedVideo``: the stored pair, uniquely constrained, with its
/// own copy of the card metadata so the list draws without refetching.
@Model
final class WatchedVideo {
    #Unique<WatchedVideo>([\.sourceID, \.itemID])

    /// The source this video came from.
    var sourceID: String = ""

    /// The source's own identifier for the video, in its normalized form.
    var itemID: String = ""

    var rawTitle: String = ""
    var thumbnail: String?
    var preview: String?
    var duration: Int = 0
    var views: String = ""
    var isHD: Bool = false
    var tags: [String] = []

    /// When it was last watched. Rewatching moves an entry rather than adding one.
    var watchedAt: Date = Date.now

    /// The playback position in seconds where the user paused or navigated away.
    /// Allows resuming from that point on the next view, without rewinding through
    /// content already seen. Remains at zero for newly watched videos.
    var playbackPosition: Int = 0

    init(video: Video, watchedAt: Date = .now) {
        self.sourceID = video.sourceID
        self.itemID = video.itemID
        self.rawTitle = video.rawTitle
        self.thumbnail = video.thumbnailURL?.absoluteString
        self.preview = video.previewURL?.absoluteString
        self.duration = video.duration
        self.views = video.views
        self.isHD = video.isHD
        self.tags = video.tags
        self.watchedAt = watchedAt
    }
}

extension WatchedVideo {
    /// The identity of the video this entry represents.
    var videoID: VideoID {
        VideoID(sourceID: sourceID, itemID: itemID)
    }

    /// The video this entry represents.
    var video: Video {
        Video(
            id: videoID,
            rawTitle: rawTitle,
            thumbnailURL: thumbnail.flatMap { URL(string: $0) },
            previewURL: preview.flatMap { URL(string: $0) },
            duration: duration,
            views: views,
            isHD: isHD,
            tags: tags
        )
    }
}

extension ModelContext {
    /// Records that a video was watched, moving it to the top if it's already there.
    ///
    /// Watching the same video twice should read as one entry that moved, not two
    /// entries — so this updates the date rather than inserting a duplicate. The
    /// uniqueness constraint would collapse them anyway, but silently and keeping
    /// whichever date SwiftData preferred.
    func recordWatch(_ video: Video, at date: Date = .now) {
        let sourceID = video.sourceID
        let itemID = video.itemID
        let descriptor = FetchDescriptor<WatchedVideo>(
            predicate: #Predicate { $0.sourceID == sourceID && $0.itemID == itemID }
        )
        if let existing = try? fetch(descriptor).first {
            existing.watchedAt = date
        } else {
            insert(WatchedVideo(video: video, watchedAt: date))
        }
        try? save()
        trimHistory()
    }

    /// Forgets every watched video.
    func clearHistory() {
        try? delete(model: WatchedVideo.self)
        try? save()
    }

    /// Keeps history to a sane length, oldest dropped first.
    ///
    /// Without a cap this grows for the life of the install, and every entry carries
    /// its own copy of the card metadata.
    private func trimHistory(limit: Int = 500) {
        var descriptor = FetchDescriptor<WatchedVideo>(
            sortBy: [SortDescriptor(\.watchedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit + 100
        guard let entries = try? fetch(descriptor), entries.count > limit else { return }
        for entry in entries[limit...] { delete(entry) }
        try? save()
    }
}
