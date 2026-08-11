/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A model class that defines a video a person saves for later.
*/

import Foundation
import SwiftData

/// A model class that defines a video a person saves for later.
///
/// Identity is the stored pair of ``sourceID`` and ``itemID``, enforced by a
/// compound uniqueness constraint. Nothing persists the combined text form: a
/// person's library shouldn't depend on a separator character, and renaming a
/// source becomes an update to one field instead of a string migration.
///
/// The app's catalog lives on remote sites, so a saved video also stores its own
/// copy of everything the interface needs to draw a card. That keeps the Saved tab
/// usable without refetching a listing page — from any source.
@Model
final class SavedVideo {
    #Unique<SavedVideo>([\.sourceID, \.itemID])

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
    var createdAt: Date = Date.now

    init(video: Video, createdAt: Date = .now) {
        self.sourceID = video.sourceID
        self.itemID = video.itemID
        self.rawTitle = video.rawTitle
        self.thumbnail = video.thumbnailURL?.absoluteString
        self.preview = video.previewURL?.absoluteString
        self.duration = video.duration
        self.views = video.views
        self.isHD = video.isHD
        self.tags = video.tags
        self.createdAt = createdAt
    }
}

extension SavedVideo {
    /// The identity of the video this item represents.
    var videoID: VideoID {
        VideoID(sourceID: sourceID, itemID: itemID)
    }

    /// The video this item represents.
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
    /// Returns the saved item for the specified video, if there is one.
    func savedVideo(for id: VideoID) -> SavedVideo? {
        let sourceID = id.sourceID
        let itemID = id.itemID
        var descriptor = FetchDescriptor<SavedVideo>(
            predicate: #Predicate { $0.sourceID == sourceID && $0.itemID == itemID }
        )
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    /// Adds the video to the saved list, or removes it if it's already there.
    /// - Returns: A Boolean value that indicates whether the video is now saved.
    @discardableResult
    func toggleSaved(_ video: Video) -> Bool {
        if let existing = savedVideo(for: video.id) {
            delete(existing)
            try? save()
            return false
        }
        insert(SavedVideo(video: video))
        try? save()
        return true
    }
}
