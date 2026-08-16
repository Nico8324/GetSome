/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that presents the video content details.
*/

import SwiftUI
import SwiftData
import CoreMedia

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
    @State private var isLoadingDetails = false
    /// The rendition that will actually play, once the sources are known.
    @State private var playbackHeight: Int?
    @State private var detailError: String?
    @State private var viewSize: CGSize = CGSize(width: 0, height: 0)
    @State private var uploaderName: String?
    @State private var uploaderFeed: Feed?
    @State private var sceneThumbnails: [URL] = []

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
                        // The error and its exit in one place: most failures here
                        // are a hiccup on the site's side, and re-entering the
                        // screen was the only retry the app used to offer.
                        HStack(spacing: Constants.genreSpacing) {
                            Text(detailError)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Retry") {
                                Task { await loadDetails() }
                            }
                            .font(.footnote.bold())
                        }
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

                    if !sceneThumbnails.isEmpty {
                        Text("Scenes")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Constants.genreSpacing) {
                                ForEach(Array(sceneThumbnails.enumerated()), id: \.element) { index, url in
                                    Button {
                                        player.loadVideo(video, presentation: .fullWindow,
                                                         startTime: sceneStart(at: index))
                                    } label: {
                                        PosterImageView(url: url, sourceID: video.sourceID)
                                            .frame(width: 148, height: 84)
                                            .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius))
                                            .overlay(alignment: .bottomTrailing) {
                                                if let label = sceneTimeLabel(at: index) {
                                                    Text(label)
                                                        .font(.caption2.monospacedDigit())
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 2)
                                                        .background(.black.opacity(0.6), in: .rect(cornerRadius: 4))
                                                        .padding(4)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!video.isAvailable || video.duration <= 0)
                                    .accessibilityLabel(sceneTimeLabel(at: index).map {
                                        String(localized: "Play from \($0)",
                                               comment: "An accessible label for a scene thumbnail that starts playback at a time")
                                    } ?? String(localized: "Scenes"))
                                }
                            }
                        }
                        .scrollClipDisabled()
                    }

                    if let feed = uploaderFeed {
                        Text("Uploader")
                            .font(.headline)
                        // Pushed directly rather than through NavigationNode.feed:
                        // that route resolves its Feed from the static registry,
                        // and an uploader's feed is built on the fly from the watch
                        // page — the registry has never heard of it.
                        NavigationLink {
                            // isRoot false: this sits inside the existing stack,
                            // and a nested NavigationStack would trap navigation.
                            FeedView(feed: feed, namespace: namespace, isRoot: false)
                                #if os(iOS)
                                .toolbarRole(.editor)
                                #endif
                        } label: {
                            HStack {
                                Text(feed.name)
                                    .foregroundStyle(.tint)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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

    /// The moment a scene thumbnail stands for.
    ///
    /// Sites publish these as a strip without saying when each was taken, so the
    /// offset is inferred: *n* thumbnails spread evenly across the running time.
    /// That's an approximation, and it's why tapping one is offered as "start
    /// around here" rather than as frame-accurate seeking — close enough to land in
    /// the right scene, which is the whole point of the strip.
    private func sceneStart(at index: Int) -> CMTime? {
        guard video.duration > 0, !sceneThumbnails.isEmpty else { return nil }
        let seconds = Double(video.duration) * Double(index) / Double(sceneThumbnails.count)
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func sceneTimeLabel(at index: Int) -> String? {
        guard let start = sceneStart(at: index) else { return nil }
        return Duration.seconds(start.seconds).formatted(.time(pattern: .minuteSecond))
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
            uploaderName = details.uploaderName
            uploaderFeed = details.uploaderFeed
            sceneThumbnails = details.sceneThumbnailURLs
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
    /// The source to search. A keyword only means something on the site it came from.
    let sourceID: String
    let keywords: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Constants.genreSpacing) {
                ForEach(keywords, id: \.self) { keyword in
                    // Searched everywhere, not just on the site that published it:
                    // the word is this site's, but what it names isn't. See
                    // ContentClient.videos(matchingEverywhere:).
                    NavigationLink(value: NavigationNode.tag(sourceID: FeedStore.allSitesID, keyword: keyword)) {
                        // Shown as published, never translated: the chip triggers
                        // a search, and a site only knows its own keywords — while
                        // machine translation, given a bare tag, turns "fishnet"
                        // into fishing equipment. See TagView.
                        Text(keyword)
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
