/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that loads a video's poster image from the source site.
*/

import SwiftUI
import ImageIO

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
                placeholder
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
        guard let data, let platformImage = Self.decodedImage(from: data) else {
            didFail = true
            return
        }
        withAnimation(.easeIn(duration: 0.2)) {
            image = Image(platformImage: platformImage)
        }
    }

    /// Decodes poster bytes at card size rather than full size.
    ///
    /// Every visible cell used to decode its poster at the CDN's native
    /// resolution and let the GPU scale it down — dozens of times per screen of
    /// scrolling, which is the kind of steady background work a phone answers
    /// with heat. 600 pixels comfortably covers the widest card on the densest
    /// display, and 900 leaves headroom for the hero, whose source images are
    /// barely bigger than that anyway.
    private static func decodedImage(from data: Data) -> PlatformImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 900
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return PlatformImage(data: data)
        }
        #if os(macOS)
        return PlatformImage(cgImage: cgImage, size: .zero)
        #else
        return PlatformImage(cgImage: cgImage)
        #endif
    }

    /// While loading, a quiet gradient rather than an icon: a grid of icons reads
    /// as a screen full of broken images when it's really just a slow network.
    /// Only an actual failure earns a symbol.
    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.16), Color(white: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if didFail {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
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
