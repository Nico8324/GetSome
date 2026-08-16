/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that represents a video card.
*/
import SwiftUI

/// Constants that represent the supported styles for video cards.
enum VideoCardStyle {

    /// A style for a full video card.
    ///
    /// This style presents a poster image on top and information about the video
    /// below, including its keywords.
    case full

    /// A style for cards in the Up Next list.
    ///
    /// This style presents a medium-sized poster image on top and a title string below.
    case upNext

    /// A style for cards in the browse and saved grids.
    ///
    /// This style presents a medium sized poster image with a title string below.
    case grid

    /// A style for cards in a feed list.
    ///
    /// This style presents an image on the leading edge with information about
    /// the video on the trailing edge.
    case stack

    /// A style for the shorter rows in the watch now view.
    ///
    /// This style presents a medium-sized poster image on top and a title string below.
    case half

}

/// A view that represents a video in the library.
///
/// A user can select a video card to view the video details.
struct VideoCardView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(TranslationStore.self) private var translator
    @Environment(PlayerModel.self) private var player
    @Environment(\.modelContext) private var context

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    var video: Video
    var style: VideoCardStyle = .full

    private var poster: some View {
        // `.fit` sizes the tile itself to 16:9 from whatever width it's given, so
        // cards can't stretch to different heights. The image inside still fills
        // and crops — see PosterImageView.
        PosterImageView(url: video.thumbnailURL, sourceID: video.sourceID)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipped()
            .overlay { PosterBadgeOverlay(video: video) }
    }

    var body: some View {
        #if os(tvOS)
        card
        #else
        // A long press answers the question a card can't: "what is this,
        // really?" — the site's own preview clip, plus the actions that
        // otherwise cost a trip into the detail screen.
        card.contextMenu {
            Button {
                player.loadVideo(video, presentation: .fullWindow)
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            Button {
                _ = context.toggleSaved(video)
            } label: {
                if context.savedVideo(for: video.id) != nil {
                    Label("Remove from Saved", systemImage: "heart.slash")
                } else {
                    Label("Save", systemImage: "heart")
                }
            }
            if let pageURL = ContentSources.source(with: video.sourceID)?.watchURL(forItem: video.itemID) {
                ShareLink(item: pageURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        } preview: {
            // The same clip the hero plays, at card size. The poster paints
            // first, so a slow or expired preview still shows something.
            PosterImageView(url: video.thumbnailURL, sourceID: video.sourceID)
                .overlay {
                    if let preview = video.previewURL {
                        HeroPreviewView(url: preview, sourceID: video.sourceID)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(width: Constants.videoCardWidth)
        }
        #endif
    }

    @ViewBuilder
    private var card: some View {
        switch style {
        case .half:
            PosterCard(poster: poster, title: translator.text(for: video.name))
                .frame(width: isCompact ? Constants.compactVideoCardWidth : Constants.videoCardWidth)
                .clipShape(.rect(cornerRadius: Constants.cornerRadius))
                #if os(iOS) || os(visionOS)
                .hoverEffect()
                #endif

        case .upNext:
            PosterCard(poster: poster, title: translator.text(for: video.name))
                .frame(width: Constants.upNextVideoCardWidth)
                .clipShape(.rect(cornerRadius: Constants.cornerRadius))
                #if os(iOS) || os(visionOS)
                .hoverEffect()
                #endif

        case .full:
            VStack(spacing: 0) {
                poster

                InfoView(video: video)
            }
            #if os(macOS)
            .background(.quaternary)
            #else
            .background(.ultraThinMaterial)
            #endif
            #if os(iOS) || os(visionOS)
            .hoverEffect()
            #endif
            .frame(width: isCompact ? Constants.compactVideoCardWidth : Constants.videoCardWidth)
            .clipShape(.rect(cornerRadius: Constants.cornerRadius))

        case .grid:
            PosterCard(poster: poster, title: translator.text(for: video.name))
                #if os(iOS) || os(visionOS)
                .hoverEffect()
                #endif

        case .stack:
            HStack(spacing: 0) {
                poster
                    .frame(maxWidth: isCompact ? Constants.stackImageCompactWidth : Constants.stackImageWidth)
                    .cornerRadius(Constants.cornerRadius)
                    .padding([.leading, .vertical], Constants.cardPadding)

                InfoView(video: video)
            }
            #if os(macOS)
            .background(.quaternary)
            #else
            .background(.ultraThinMaterial)
            #endif
            #if os(iOS) || os(visionOS)
            .hoverEffect()
            #endif
            .cornerRadius(Constants.cornerRadius)
        }
    }
}

#Preview("Full", traits: .previewData) {
    VideoCardView(video: .preview, style: .full)
        .frame(height: 350)
}

#Preview("Grid", traits: .previewData) {
    VideoCardView(video: .preview, style: .grid)
        .frame(width: 200, height: 200)
}

#Preview("Stack", traits: .previewData) {
    VideoCardView(video: .preview, style: .stack)
        .frame(height: 200)
}
