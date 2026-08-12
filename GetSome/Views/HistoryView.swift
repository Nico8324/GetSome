/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that displays the videos a person watched.
*/

import SwiftUI
import SwiftData

/// A view that displays the videos a person watched.
///
/// The record is the app's own, so this covers every source rather than the one
/// site that happens to offer history — and it needs no account.
struct HistoryView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \WatchedVideo.watchedAt, order: .reverse)
    private var watched: [WatchedVideo]

    @Namespace private var namespace
    @State private var isConfirmingClear = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            if watched.isEmpty {
                ContentUnavailableView(
                    "Nothing watched yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Videos you play show up here.")
                )
                .padding(.top, Constants.outerPadding * 3)
            } else {
                VideoGridView(videos: watched.map(\.video), namespace: namespace)
                    .padding(Constants.outerPadding)
            }
        }
        .scrollClipDisabled()
        .navigationTitle("History")
        .navigationDestinationVideo(in: namespace)
        #if !os(tvOS)
        .toolbar {
            if !watched.isEmpty {
                Button("Clear", systemImage: "trash") {
                    isConfirmingClear = true
                }
            }
        }
        #endif
        .confirmationDialog("Clear watch history?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) {
                context.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This forgets every video you watched on this device. It can’t be undone.")
        }
    }
}

#Preview(traits: .previewData) {
    NavigationStack { HistoryView() }
}
