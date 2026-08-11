/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that displays the videos a person saved for later.
*/

import SwiftUI
import SwiftData

/// A view that displays the videos a person saved for later.
struct SavedView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \SavedVideo.createdAt, order: .reverse)
    private var saved: [SavedVideo]

    @Namespace private var namespace
    @State private var navigationPath = [NavigationNode]()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView(showsIndicators: false) {
                if saved.isEmpty {
                    ContentUnavailableView(
                        "Nothing saved yet",
                        systemImage: "heart",
                        description: Text("Tap Save on a video to keep it here.")
                    )
                    .padding(.top, Constants.outerPadding * 3)
                } else {
                    VideoGridView(videos: saved.map(\.video), namespace: namespace)
                        .padding(Constants.outerPadding)
                }
            }
            .scrollClipDisabled()
            .navigationDestinationVideo(in: namespace)
            #if !os(tvOS)
            .toolbar {
                if !saved.isEmpty {
                    Button("Remove All", systemImage: "trash") {
                        for item in saved {
                            context.delete(item)
                        }
                        try? context.save()
                    }
                }
            }
            #endif
        }
    }
}

#Preview(traits: .previewData) {
    SavedView()
}
