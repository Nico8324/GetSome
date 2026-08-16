/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A thin progress bar indicating playback position within a video.
*/

import SwiftUI

/// A thin progress bar showing playback progress as a portion of total duration.
///
/// The view displays a capsule-shaped track with a filled portion representing
/// the progress ratio. Progress is automatically clamped to the 0–1 range, so
/// callers can pass raw position/duration fractions without bounds-checking.
struct WatchProgressBar: View {
    /// Progress as a normalized value between 0 and 1.
    let progress: Double

    private let trackHeight: Double = 3

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track background in a subtle gray tone.
                Capsule()
                    .fill(.quaternary)

                // Filled portion matching the app's accent tint.
                Capsule()
                    .fill(.tint)
                    .frame(width: geometry.size.width * min(max(progress, 0), 1))
            }
            .frame(height: trackHeight)
        }
        .frame(height: trackHeight)
    }
}

#Preview {
    VStack(spacing: 16) {
        WatchProgressBar(progress: 0.0)
        WatchProgressBar(progress: 0.33)
        WatchProgressBar(progress: 0.66)
        WatchProgressBar(progress: 1.0)
    }
    .padding()
}
