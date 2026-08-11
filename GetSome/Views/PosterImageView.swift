/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that loads a video's poster image from the source site.
*/

import SwiftUI

/// A view that loads a video's poster image from the source site.
///
/// This deliberately doesn't use `AsyncImage`. Posters have to be requested the
/// way their site expects — at least one image CDN answers 403 to a request with
/// no user agent or referer — so loading goes through ``ContentClient``, which
/// applies the source's own headers and caches the bytes.
struct PosterImageView: View {
    let url: URL?

    /// The site the poster belongs to, which decides the request headers.
    var sourceID: String?

    var contentMode: ContentMode = .fill

    @State private var image: Image?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder(systemImage: didFail ? "photo.badge.exclamationmark" : "play.rectangle")
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        image = nil
        didFail = false
        guard let url else { return }

        let data = await ContentClient.shared.imageData(at: url, from: sourceID ?? "")
        guard let data, let platformImage = PlatformImage(data: data) else {
            didFail = true
            return
        }
        withAnimation(.easeIn(duration: 0.2)) {
            image = Image(platformImage: platformImage)
        }
    }

    private func placeholder(systemImage: String) -> some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tertiary)
        }
    }
}

/// A view that overlays a video's duration and quality on its poster image.
struct PosterBadgeOverlay: View {
    let video: Video

    var body: some View {
        VStack {
            HStack {
                if video.isHD {
                    Text("HD")
                        .font(.caption2.bold())
                        .padding(.horizontal, Constants.genreHorizontalPadding)
                        .padding(.vertical, Constants.genreVerticalPadding)
                        .background(.thinMaterial, in: .rect(cornerRadius: 4))
                }
                Spacer()
                // A saved video whose site the app no longer ships can't be played.
                if !video.isAvailable {
                    Label("Unavailable", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly)
                        .font(.caption)
                        .padding(Constants.genreVerticalPadding)
                        .background(.thinMaterial, in: .circle)
                        .accessibilityLabel("This video’s site is no longer available")
                }
            }
            Spacer()
            HStack {
                Spacer()
                Text(video.formattedDuration)
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, Constants.genreHorizontalPadding)
                    .padding(.vertical, Constants.genreVerticalPadding)
                    .background(.thinMaterial, in: .rect(cornerRadius: 4))
            }
        }
        .padding(Constants.genreSpacing)
    }
}
