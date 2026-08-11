/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A modifier that creates the environment that previews need.
*/

import Foundation
import SwiftData
import SwiftUI

/// A modifier that supplies previews with in-memory storage and the app's model objects.
struct PreviewData: PreviewModifier {
    static func makeSharedContext() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SavedVideo.self, configurations: config)
    }

    func body(content: Content, context: ModelContainer) -> some View {
        content.modelContainer(context)
            .environment(PlayerModel())
            .environment(FeedStore())
            .environment(TranslationStore())
            #if os(visionOS)
            .environment(ImmersiveEnvironment())
            #endif
            #if os(iOS) || os(macOS)
            .preferredColorScheme(.dark)
            #endif
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    @MainActor static var previewData: Self = .modifier(PreviewData())
}

extension Video {
    /// A video that previews use to lay out their content.
    static let preview = Video(
        id: VideoID(sourceID: "mat6tube", itemID: "-13001002_456239834"),
        rawTitle: "A sample title from the source site [hd,amateur,couple]",
        thumbnailURL: nil,
        duration: 2099,
        views: "653.81K",
        isHD: true
    )
}
