/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A model object that manages the playback of video.
*/

import AVKit
import GroupActivities

/// The presentation modes the player supports.
enum Presentation {
    /// Presents the player as a child of a parent user interface.
    case inline
    /// Presents the player in full-window exclusive mode.
    case fullWindow
}

/// A model object that manages the playback of video.
@MainActor @Observable class PlayerModel {

    /// A Boolean value that indicates whether playback is currently active.
    private(set) var isPlaying = false

    /// A Boolean value that indicates whether playback of the current item is complete.
    private(set) var isPlaybackComplete = false

    /// The presentation in which to display the current media.
    private(set) var presentation: Presentation = .inline

    /// The currently loaded video.
    private(set) var currentItem: Video? = nil

    /// A Boolean value that indicates whether the app is resolving a stream for the current video.
    private(set) var isResolvingStream = false

    /// A description of the most recent failure to load a video, if there is one.
    private(set) var loadError: String? = nil

    /// The vertical resolution now playing, when the source published one.
    ///
    /// AVKit offers no quality control for a single rendition — and no way to ask
    /// what it's playing — so the app tracks the height it chose and surfaces it.
    private(set) var currentHeight: Int?

    /// A Boolean value that indicates whether the player should propose playing the next saved video.
    private(set) var shouldProposeNextVideo = false

    /// An object that manages the playback of a video's media.
    private var player: AVPlayer

    /// The currently presented platform-specific video player user interface.
    ///
    /// On iOS, tvOS, and visionOS, the app uses `AVPlayerViewController` to present the video player user interface.
    /// The life cycle of an `AVPlayerViewController` object is different than a typical view controller. In addition
    /// to displaying the video player UI within your app, the view controller also manages the presentation of the media
    /// outside your app's UI such as when using AirPlay, Picture in Picture, or docked full window. To ensure the view
    /// controller instance is preserved in these cases, the app stores a reference to it here
    /// as an environment-scoped object.
    ///
    /// Call the `makePlayerUI()` method to set this value.
    private var playerUI: AnyObject? = nil
    private var playerUIDelegate: AnyObject? = nil

    private(set) var shouldAutoPlay = true

    /// An object that manages the app's SharePlay implementation.
    private var coordinator: WatchingCoordinator

    /// A token for periodic observation of the video player's time.
    private var timeObserver: Any? = nil

    private var playerObservationToken: NSKeyValueObservation?

    /// The task that resolves a stream URL for the current video.
    private var loadTask: Task<Void, Never>?

    /// The object that loads content from the source site.
    private let client: ContentClient

    init(client: ContentClient = .shared) {
        let player = AVPlayer()

        self.client = client
        self.coordinator = WatchingCoordinator(coordinator: player.playbackCoordinator)
        self.player = player

        observePlayback()
        observeSharedVideo()
        configureAudioSession()
    }

    #if os(macOS)
    /// Creates a new player view object.
    /// - Returns: a configured player view.
    func makePlayerUI() -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player

        // Set the model state
        playerUI = playerView
        playerUIDelegate = nil

        return playerView
    }
    #else
    /// Creates a new player view controller object.
    /// - Returns: a configured player view controller.
    func makePlayerUI() -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        playerUI = controller

        #if os(visionOS)
        @MainActor
        class PlayerViewObserver: NSObject, AVPlayerViewControllerDelegate {
            private var continuation: CheckedContinuation<Void, Never>?

            func willEndFullScreenPresentation() async {
                await withCheckedContinuation {
                    continuation = $0
                }
            }

            nonisolated func playerViewController(
                _ playerViewController: AVPlayerViewController,
                willEndFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator
            ) {
                Task { @MainActor in
                    continuation?.resume()
                }
            }
        }

        let observer = PlayerViewObserver()
        controller.delegate = observer
        playerUIDelegate = observer

        Task {
            await observer.willEndFullScreenPresentation()
            reset()
        }
        #endif

        return controller
    }
    #endif

    private func observePlayback() {
        // Return early if the model calls this more than once.
        guard playerObservationToken == nil else { return }

        // Observe the time control status to determine whether playback is active.
        playerObservationToken = player.observe(\.timeControlStatus) { observed, _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = observed.timeControlStatus == .playing
            }
        }

        let center = NotificationCenter.default

        // Observe this notification to identify when a video plays to its end.
        Task {
            for await _ in center.notifications(named: .AVPlayerItemDidPlayToEndTime) {
                isPlaybackComplete = true
            }
        }

        #if !os(macOS)
        // Observe audio session interruptions.
        Task {
            for await notification in center.notifications(named: AVAudioSession.interruptionNotification) {
                guard let result = InterruptionResult(notification) else { continue }
                // Resume playback, if appropriate.
                if result.type == .ended && result.options == .shouldResume {
                    player.play()
                }
            }
        }
        #endif

        // Add an observer of the player object's current time. The app observes
        // the player's current time to determine when to propose playing the next
        // video in the saved list.
        addTimeObserver()
    }

    /// Configures the audio session for video playback.
    private func configureAudioSession() {
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // Configure the audio session for playback. Set the `moviePlayback` mode
            // to reduce the audio's dynamic range to help normalize audio levels.
            try session.setCategory(.playback, mode: .moviePlayback)
        } catch {
            logger.error("Unable to configure audio session: \(error.localizedDescription)")
        }
        #endif
    }

    /// Monitors the coordinator's `sharedVideo` property.
    ///
    /// If this value changes due to a remote participant sharing a new activity, load and present the new video.
    private func observeSharedVideo() {
        Task {
            for await _ in NotificationCenter.default.notifications(named: .liveVideoDidChange) {
                guard let liveVideoID = coordinator.liveVideoID,
                      liveVideoID != currentItem?.id
                else { continue }
                await loadVideo(withID: liveVideoID, presentation: .fullWindow)
            }
        }
    }

    /// Loads a video that only its identifier is known for, such as one a SharePlay participant starts.
    private func loadVideo(
        withID videoID: VideoID,
        presentation: Presentation = .inline
    ) async {
        let placeholder = Video(id: videoID)
        do {
            let video = try await client.details(for: placeholder).video ?? placeholder
            loadVideo(video, presentation: presentation)
        } catch {
            logger.debug("\(error.localizedDescription)")
        }
    }

    /// Loads a video for playback in the requested presentation.
    ///
    /// The source site signs its media URLs and expires them, so the app resolves a
    /// stream at the moment of playback rather than storing one alongside the video.
    ///
    /// - Parameters:
    ///   - video: The video to load for playback.
    ///   - presentation: The style in which to present the player.
    ///   - autoplay: A Boolean value that indicates whether to automatically play the content when presented.
    ///   - usePreview: A Boolean value that indicates whether to play the site's short preview clip
    ///     instead of the full video.
    func loadVideo(
        _ video: Video,
        presentation: Presentation = .inline,
        autoplay: Bool = true,
        usePreview: Bool = false
    ) {
        // Update the model state for the request.
        currentItem = video
        shouldAutoPlay = autoplay
        isPlaybackComplete = false
        loadError = nil

        loadTask?.cancel()
        loadTask = Task {
            // Attempt to SharePlay this video if a FaceTime call is active.
            if presentation == .fullWindow {
                await coordinator.coordinatePlaybackOfVideo(video)
            }
            await resolveAndEnqueue(video, usePreview: usePreview, autoplay: autoplay)
        }

        // In visionOS, configure the spatial experience for either .inline or .fullWindow playback.
        configureAudioExperience(for: presentation)

        // Set the presentation, which typically presents the player full window.
        self.presentation = presentation
    }

    /// Resolves a media URL for the video and hands it to the player.
    private func resolveAndEnqueue(_ video: Video, usePreview: Bool, autoplay: Bool) async {
        isResolvingStream = true
        defer { isResolvingStream = false }

        let url: URL
        if usePreview, let previewURL = video.previewURL {
            url = previewURL
            currentHeight = nil
        } else {
            do {
                let stream = try await client.stream(for: video)
                url = stream.url
                currentHeight = stream.height > 0 ? stream.height : nil
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Unable to resolve a stream for \(video.id): \(error.localizedDescription)")
                loadError = error.localizedDescription
                return
            }
        }

        guard !Task.isCancelled, currentItem?.id == video.id else { return }

        let playerItem = AVPlayerItem(url: url)
        applyQualityCeiling(to: playerItem)
        #if !os(macOS)
        playerItem.externalMetadata = await createMetadataItems(for: video)
        #endif
        player.replaceCurrentItem(with: playerItem)
        logger.debug("🍿 \(video.name) enqueued for playback.")

        if autoplay {
            player.play()
        }
    }

    /// Applies the person's Maximum Quality setting to an adaptive stream.
    ///
    /// For a fixed rendition the source already chose one, but an HLS manifest
    /// leaves the choice to the player — so without this the setting would appear
    /// to do nothing on sources that serve adaptive streams.
    private func applyQualityCeiling(to item: AVPlayerItem) {
        let quality = PlaybackSettings.maximumQuality
        guard quality != .auto else { return }
        let height = Double(quality.ceiling)
        item.preferredMaximumResolution = CGSize(width: height * 16 / 9, height: height)
    }

    /// Clears any loaded media and resets the player model to its default state.
    func reset() {
        loadTask?.cancel()
        loadTask = nil
        currentItem = nil
        loadError = nil
        currentHeight = nil
        isResolvingStream = false
        player.replaceCurrentItem(with: nil)
        playerUI = nil
        playerUIDelegate = nil
        // Reset the presentation state on the next cycle of the run loop.
        Task {
            presentation = .inline
        }
    }

    /// Creates metadata items from the video items data.
    /// - Parameter video: the video to create metadata for.
    /// - Returns: An array of `AVMetadataItem` to set on a player item.
    private func createMetadataItems(for video: Video) async -> [AVMetadataItem] {
        // The height rides along in the title because it's the one field AVKit
        // reliably shows during playback, and the player has no quality readout
        // of its own.
        let title = currentHeight.map { "\(video.name) · \($0)p" } ?? video.name

        var mapping: [AVMetadataIdentifier: Any] = [
            .commonIdentifierTitle: title,
            .commonIdentifierDescription: video.synopsis,
            .iTunesMetadataContentRating: "18+"
        ]
        if let artwork = await artworkData(for: video) {
            mapping[.commonIdentifierArtwork] = artwork
        }
        if !video.keywords.isEmpty {
            mapping[.quickTimeMetadataGenre] = video.keywords.joined(separator: ", ")
        }
        return mapping.compactMap { createMetadataItem(for: $0, value: $1) }
    }

    /// Downloads the video's poster image to show in the system playback interface.
    private func artworkData(for video: Video) async -> Data? {
        guard let url = video.thumbnailURL else { return nil }
        return await client.imageData(at: url, from: video.sourceID)
    }

    /// Creates a metadata item for a the specified identifier and value.
    /// - Parameters:
    ///   - identifier: an identifier for the item.
    ///   - value: a value to associate with the item.
    /// - Returns: a new `AVMetadataItem` object.
    private func createMetadataItem(for identifier: AVMetadataIdentifier,
                                    value: Any) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as? NSCopying & NSObjectProtocol
        // Specify "und" to indicate an undefined language.
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }

    /// Configures the spatial audio experience to best fit the presentation.
    /// - Parameter presentation: the requested player presentation.
    private func configureAudioExperience(for presentation: Presentation) {
        #if os(visionOS)
        do {
            let experience: AVAudioSessionSpatialExperience
            switch presentation {
            case .inline:
                // Set a small, focused sound stage when watching previews.
                experience = .headTracked(soundStageSize: .small, anchoringStrategy: .automatic)
            case .fullWindow:
                // Set a large sound stage size when viewing full window.
                experience = .headTracked(soundStageSize: .large, anchoringStrategy: .automatic)
            }
            try AVAudioSession.sharedInstance().setIntendedSpatialExperience(experience)
        } catch {
            logger.error("Unable to set the intended spatial experience. \(error.localizedDescription)")
        }
        #endif
    }

    // MARK: - Transport Control

    func play() {
        player.play()
    }

    func seek() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func togglePlayback() {
        player.timeControlStatus == .paused ? play() : pause()
    }

    // MARK: - Time Observation
    private func addTimeObserver() {
        removeTimeObserver()
        // Observe the player's timing once every second.
        let timeInterval = CMTime(value: 1, timescale: 1)
        timeObserver = player
            .addPeriodicTimeObserver(forInterval: timeInterval, queue: .main) { time in
                Task { @MainActor in
                    if let duration = self.player.currentItem?.duration, duration.isNumeric {
                        let isInProposalRange = time.seconds >= duration.seconds - 10.0
                        if self.shouldProposeNextVideo != isInProposalRange {
                            self.shouldProposeNextVideo = isInProposalRange
                        }
                    }
                }
            }
    }

    private func removeTimeObserver() {
        guard let timeObserver = timeObserver else { return }
        player.removeTimeObserver(timeObserver)
        self.timeObserver = nil
    }
}
