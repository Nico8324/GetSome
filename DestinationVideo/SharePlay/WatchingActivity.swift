/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A group activity to watch a video with others.
*/

import GroupActivities
import CoreTransferable
import CoreGraphics
import UniformTypeIdentifiers

/// A group activity to watch a video with others.
struct WatchingActivity: GroupActivity {
    let title: String
    let previewImageName: String
    let fallbackURL: URL?
    
    let videoID: Video.ID
    
    // Metadata that the system displays to participants.
    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.type = .watchTogether
        metadata.title = title
        metadata.previewImage = previewImage
        metadata.fallbackURL = fallbackURL
        metadata.supportsContinuationOnTV = true
        return metadata
    }
    
    var previewImage: CGImage? {
        PlatformImage(named: previewImageName)?.cgImage
    }
}

extension WatchingActivity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: WatchingActivity.self, contentType: .watchingActivity)
    }
}

extension UTType {
    static let watchingActivity = UTType(exportedAs: "com.example.apple-samplecode.DestinationVideo.WatchingActivity")
}
