/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that displays the hero video banner.
*/

import SwiftUI

/// A view that displays the hero video banner.
struct HeroView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(TranslationStore.self) private var translator

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    let video: Video
    let namespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .leading) {
            Group {
                PosterImageView(url: video.thumbnailURL, sourceID: video.sourceID)
                    .frame(maxHeight: Constants.heroViewHeight)
                    .clipped()

                // Add a subtle gradient to make the text stand out.
                GradientView(style: .black.opacity(0.6), startPoint: .leading)
                #if os(iOS)
                GradientView(style: .black, height: isCompact ? Constants.compactGradientSize : Constants.gradientSize / 2, startPoint: .bottom)
                #endif
            }

            VStack(alignment: .leading, spacing: Constants.verticalTextSpacing) {
                Text(translator.text(for: video.name))
                    .font(isCompact ? .title : .largeTitle)
                    .fontWeight(.bold)
                    .lineLimit(3)

                Text(video.subtitle)
                    .font(isCompact ? .caption : .body)
                    .fontWeight(isCompact ? .regular : .semibold)

                NavigationLink("Details", value: NavigationNode.video(video.id))
                    #if os(iOS)
                    .buttonStyle(CustomButtonStyle())
                    #endif
            }
            .frame(maxWidth: Constants.heroTextMargin, alignment: .leading)
            .padding(Constants.outerPadding)
            .padding(Constants.extendSafeAreaTV)
        }
        .transitionSource(id: video.id, namespace: namespace)
        .padding(.bottom, isCompact ? 0 : nil)
        .padding(.top, isCompact ? -Constants.compactSafeAreaHeight : -Constants.heroSafeAreaHeight)
        .padding(.horizontal, -Constants.extendSafeAreaTV)
        #if os(tvOS)
        .focusSection()
        #endif
    }
}
