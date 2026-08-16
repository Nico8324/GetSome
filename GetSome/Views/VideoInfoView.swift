/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that displays information about a video including its title, length, and keywords.
*/
import SwiftUI

/// A view that displays information about a video including its title, length, and keywords.
struct InfoView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(TranslationStore.self) private var translator

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    let video: Video

    var body: some View {
        VStack(alignment: .leading) {
            // Views only. The poster's own badges already show duration and HD,
            // so repeating them here said everything twice.
            Text(video.formattedViews)
                #if os(tvOS)
                .font(.caption)
                #else
                .font(isCompact ? .caption : .headline)
                #endif
                .foregroundStyle(.secondary)

            Text(translator.text(for: video.name))
                .font(isCompact ? .body : .title3)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)

            // Two, not three: a card this narrow truncates every chip at three.
            TagView(tags: Array(video.keywords.prefix(2)))
                .frame(height: Constants.tagRowHeight, alignment: .leading)
        }
        .padding(Constants.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A view that displays a list of keywords for a video.
///
/// Keywords are shown exactly as the site publishes them, never translated.
/// They're search terms of art, not prose: out of context, machine translation
/// turns "fishnet" into fishing equipment, and the site's own search only
/// understands the original anyway — so a chip must say what tapping it asks for.
struct TagView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    let tags: [String]

    var body: some View {
        HStack(spacing: Constants.genreSpacing) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(isCompact ? .caption2 : .caption)
                    .padding(.horizontal, Constants.genreHorizontalPadding)
                    .padding(.vertical, Constants.genreVerticalPadding)
                    .background(Capsule().stroke())
                    // Natural width: phrase-length keywords are filtered out
                    // upstream, and the row clips, so a chip can't spill.
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .clipped()
    }
}

/// A view that displays a video poster image with its title.
struct PosterCard<Poster: View>: View {
    let poster: Poster
    let title: String

    var body: some View {
        #if os(tvOS)
        ZStack(alignment: .bottom) {
            poster

            // Material gradient
            GradientView(style: .ultraThinMaterial, height: 90, startPoint: .bottom)
            Text(title)
                .font(.caption.bold())
                .lineLimit(2)
                .padding()
        }
        .cornerRadius(Constants.cornerRadius)
        #else
        VStack(alignment: .leading) {
            poster
                .cornerRadius(Constants.cornerRadius)

            Text(title)
            #if os(visionOS)
                .font(.title3)
            #else
                .font(.body)
            #endif
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        #endif
    }
}

#Preview(traits: .previewData) {
    InfoView(video: .preview)
        .frame(width: Constants.videoCardWidth)
}
