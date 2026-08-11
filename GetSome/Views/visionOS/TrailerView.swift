/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that displays a poster image that you tap to watch a preview clip.
*/

import SwiftUI

///  A view that displays a poster image that you tap to watch a preview clip.
struct TrailerView: View {
    @State private var isPosterVisible = true
    @Environment(PlayerModel.self) private var model

    let video: Video

    var body: some View {
        if isPosterVisible {
            Button {
                // Loads the site's short preview clip for inline playback.
                model.loadVideo(video, usePreview: true)
                withAnimation {
                    isPosterVisible = false
                }
            } label: {
                TrailerPosterView(video: video)
            }
            .buttonStyle(.plain)
            .buttonBorderShape(.roundedRectangle)
        } else {
            PlayerView(controlsStyle: .custom)
        }
    }
}

/// A view that displays the poster image with a play button image over it.
private struct TrailerPosterView: View {
    let video: Video

    var body: some View {
        ZStack {
            PosterImageView(url: video.thumbnailURL, sourceID: video.sourceID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 2) {
                Image(systemName: "play.fill")
                    .font(.system(size: 24.0))
                    .padding(12)
                    .background(.thinMaterial)
                    .clipShape(.circle)
                Text("Preview")
                    .font(.title3)
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 1, y: 1)
            }
        }
    }
}

#Preview("Trailer View", traits: .previewData) {
    TrailerView(video: .preview)
}
