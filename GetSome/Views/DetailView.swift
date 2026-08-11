/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that presents the video content details.
*/

import SwiftUI
import SwiftData
#if os(iOS) || os(macOS)
import Translation
#endif

/// A view that presents the video content details.
struct DetailView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(PlayerModel.self) private var player
    @Environment(\.modelContext) private var context
    @Environment(TranslationStore.self) private var translator

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    @State var video: Video
    @State private var related: [Video] = []
    @State private var isSaved = false
    @State private var isShowingSystemTranslation = false
    @State private var isLoadingDetails = false
    /// The rendition that will actually play, once the sources are known.
    @State private var playbackHeight: Int?
    @State private var detailError: String?
    @State private var viewSize: CGSize = CGSize(width: 0, height: 0)

    @Namespace private var namespace

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack {
                VStack(alignment: .leading, spacing: Constants.verticalTextSpacing) {
                    Text(translator.text(for: video.name))
                        .font(isCompact ? .title : .largeTitle)
                        .bold()

                    Text(metadataLine)
                        .font(.headline)
                        .accessibilityLabel(accessibleMetadata)

                    TagView(tags: Array(video.keywords.prefix(4)))

                    if let detailError {
                        Text(detailError)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        // A button that plays the video in a full-window presentation.
                        Button {
                            /// Load the media item for full-window presentation.
                            player.loadVideo(video, presentation: .fullWindow)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .disabled(!video.isAvailable)
                        // A button that toggles whether the app saves the video.
                        Button {
                            isSaved = context.toggleSaved(video)
                        } label: {
                            Label(isSaved ? "Saved" : "Save",
                                  systemImage: isSaved ? "heart.fill" : "heart")
                        }

                        #if os(iOS) || os(macOS)
                        // The system's own translation popover — the same one Safari
                        // and Notes present. It handles its own language downloads,
                        // and shows the full title rather than the trimmed one.
                        Button {
                            isShowingSystemTranslation = true
                        } label: {
                            Label("Translate", systemImage: "character.bubble")
                        }
                        .translationPresentation(
                            isPresented: $isShowingSystemTranslation,
                            text: video.rawTitle
                        )
                        #endif

                        Spacer()
                    }
                    .buttonStyle(CustomButtonStyle())
                    // Make the buttons the same width.
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)

                }
                .padding(isCompact ? Constants.detailCompactPadding : Constants.detailPadding)
                .padding(.bottom, isCompact ? Constants.detailCompactPadding : 0)
                .padding(.trailing, isCompact ? 0 : Constants.detailTrailingPadding)
                .frame(height: viewSize.height, alignment: .bottom)
                .background(alignment: .bottom) { backgroundView }

                #if !os(tvOS)
                VStack(alignment: .leading, spacing: Constants.verticalTextSpacing) {
                    #if os(visionOS)
                    if video.previewURL != nil {
                        Text("Preview")
                            .font(.headline)

                        // A view that plays the site's short preview clip inline.
                        TrailerView(video: video)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .frame(maxWidth: Constants.trailerHeight)
                            .cornerRadius(Constants.cornerRadius)
                    }
                    #endif

                    if !video.keywords.isEmpty {
                        Text("Keywords")
                            .font(.headline)
                        KeywordLinksView(sourceID: video.sourceID, keywords: video.keywords)
                    }
                }
                .padding(isCompact ? Constants.detailCompactPadding : Constants.detailPadding)
                .padding(.bottom, isCompact ? Constants.detailCompactPadding : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                #endif

                if !related.isEmpty {
                    VideoListView(title: "Related",
                                  videos: related,
                                  cardStyle: .half,
                                  namespace: namespace)
                    .padding(.bottom, Constants.outerPadding)
                } else if isLoadingDetails {
                    ProgressView()
                        .padding(.bottom, Constants.outerPadding)
                }
            }
            #if os(iOS)
            .background(.black)
            #endif
        }
        .scrollClipDisabled()
        .padding(.top, isCompact ? -Constants.compactDetailSafeAreaHeight : -Constants.detailSafeAreaHeight)
        .onGeometryChange(for: CGSize.self) { proxy in
            return proxy.size
        } action: { size in
            let heightPadding = (isCompact ? Constants.compactDetailSafeAreaHeight : Constants.detailSafeAreaHeight)
            let widthPadding = Constants.extendSafeAreaTV
            viewSize = CGSize(width: size.width + widthPadding, height: size.height + heightPadding)
        }
        // Don't show a navigation title in iOS.
        .navigationTitle("")
        .toolbarBackground(.hidden)
        .task(id: video.id) {
            isSaved = context.savedVideo(for: video.id) != nil
            await loadDetails()
        }
    }

    private var metadataLine: String {
        // Prefer the real rendition over a generic HD badge: it's the height that
        // will actually play, chosen from what the source offers and the person's
        // Maximum Quality setting.
        let quality = playbackHeight.map { "\($0)p" } ?? (video.isHD ? "HD" : "")
        var parts = [video.formattedDuration, video.formattedViews, video.formattedUploadDate, quality]
        // Name the site only when the app browses more than one.
        if ContentSources.hasMultipleSources, let source = video.source {
            parts.append(source.displayName)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " | ")
    }

    private var accessibleMetadata: String {
        String(
            localized: "\(video.formattedDuration) long, \(video.formattedViews)",
            comment: "An accessible description of a video's length and view count"
        )
    }

    /// Loads the metadata and related videos that only the watch page publishes.
    private func loadDetails() async {
        guard related.isEmpty else { return }
        isLoadingDetails = true
        defer { isLoadingDetails = false }
        do {
            let details = try await ContentClient.shared.details(for: video)
            if let complete = details.video {
                // Merge rather than replace: the watch page usually adds an upload
                // date and the full keyword list, but on some sites it publishes
                // no view count at all, and the listing's shouldn't be lost.
                video = video.merging(complete)
            }
            related = details.related
            playbackHeight = video.source
                .flatMap { $0.preferredStream(from: details.sources) }
                .map(\.height)
                .flatMap { $0 > 0 ? $0 : nil }
            detailError = nil
        } catch {
            detailError = error.localizedDescription
        }
    }

    private var backgroundView: some View {
        Group {
            PosterImageView(url: video.thumbnailURL, sourceID: video.sourceID)
                .frame(width: viewSize.width, height: viewSize.height)
                .clipped()

            // Add a subtle gradient to make the text stand out.
            #if os(iOS)
            GradientView(style: .black.opacity(0.6), direction: .horizontal, width: Constants.gradientSize, startPoint: .leading)
            GradientView(style: .black, height: Constants.gradientSize, startPoint: .bottom)
            #else
            GradientView(style: .black.opacity(0.4), direction: .horizontal, width: Constants.gradientSize, startPoint: .leading)
            GradientView(style: .black.opacity(0.5), height: Constants.gradientSize, startPoint: .bottom)
            #endif
        }
        .padding([.horizontal, .bottom], -Constants.extendSafeAreaTV)
    }
}

/// A view that presents a video's keywords as links to a search for each one.
struct KeywordLinksView: View {
    @Environment(TranslationStore.self) private var translator

    /// The source to search. A keyword only means something on the site it came from.
    let sourceID: String
    let keywords: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Constants.genreSpacing) {
                ForEach(keywords, id: \.self) { keyword in
                    NavigationLink(value: NavigationNode.tag(sourceID: sourceID, keyword: keyword)) {
                        // Search the site with the original word — a site only
                        // knows its own keywords.
                        Text(translator.text(for: keyword))
                            .font(.caption)
                            .padding(.horizontal, Constants.genreHorizontalPadding * 2)
                            .padding(.vertical, Constants.genreVerticalPadding * 2)
                            .background(Capsule().fill(.quaternary))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }
}

#Preview(traits: .previewData) {
    NavigationStack {
        DetailView(video: .preview)
    }
}
