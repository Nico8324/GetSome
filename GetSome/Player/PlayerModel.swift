/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A model object that manages the playback of video.
*/

import AVKit
import SwiftData
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

    /// Where watch history is written, handed over by ``ContentView`` once the
    /// model container exists. Nothing is recorded until it does.
    @ObservationIgnored var historyContext: ModelContext?

    /// The watch history entry for the currently playing video, used to record and
    /// restore playback position. Populated when loadVideo records a watch and cleared
    /// when playback ends or a new video loads.
    @ObservationIgnored var currentWatchedVideo: WatchedVideo?

    /// The presentation in which to display the current media.
    ///
    /// On iPhone this also decides whether the app may rotate: the rest of the app
    /// is portrait-only, and a full-window video is the one thing worth turning the
    /// device sideways for. See ``AppDelegate``.
    private(set) var presentation: Presentation = .inline {
        didSet {
            #if os(iOS)
            AppDelegate.supportedOrientations = presentation == .fullWindow ? .allButUpsideDown : .portrait
            #endif
        }
    }

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

    /// A live quality ceiling chosen from the AVKit quality menu during this session.
    ///
    /// `nil` means no live choice has been made, so the profile's Maximum Quality
    /// setting applies as usual. `.some(nil)` means the person explicitly chose
    /// Auto from the menu, which removes any ceiling regardless of the profile
    /// setting. Once set, the choice carries forward to every subsequent video
    /// loaded this session, not just the item playing when it was made.
    @ObservationIgnored private var sessionQualityCeilingHeight: Int??

    /// The video for which the app has already attempted a mid-play recovery.
    ///
    /// This app's streams are signed URLs that can expire mid-play, and an expired
    /// URL looks identical to a genuinely broken video — the only way to tell them
    /// apart is to retry once. This remembers which video already got that retry
    /// so a second failure gives up instead of retrying forever.
    @ObservationIgnored private var recoveryAttemptedVideoID: VideoID?

    /// Whether the currently loaded video is playing its short preview clip rather
    /// than the full video, so a mid-play recovery re-resolves the same kind of stream.
    @ObservationIgnored private var isPlayingPreview = false

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

        // Observe this notification as one of two signals — alongside the item
        // status check in `resolveAndEnqueue` — that playback has failed. A signed
        // stream URL expiring mid-play surfaces this way just as often as a genuine
        // playback error does, and only a retry can tell the two apart.
        Task {
            for await notification in center.notifications(named: .AVPlayerItemFailedToPlayToEndTime) {
                handlePlaybackFailure(for: notification.object as? AVPlayerItem)
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
    ///   - startTime: A moment to open at, chosen deliberately — by tapping a scene
    ///     thumbnail, say. It takes precedence over the saved watch position, which
    ///     is what "resume" means and is not what was asked for here.
    func loadVideo(
        _ video: Video,
        presentation: Presentation = .inline,
        autoplay: Bool = true,
        usePreview: Bool = false,
        startTime: CMTime? = nil
    ) {
        // Save the playback position of the currently playing video before loading
        // a new one, so switching videos doesn't abandon the user's progress.
        updatePlaybackPosition()
        currentWatchedVideo = nil

        // Update the model state for the request.
        currentItem = video
        shouldAutoPlay = autoplay
        isPlaybackComplete = false
        loadError = nil
        // A new video gets its own fresh recovery attempt, independent of whatever
        // happened to the one playing before it.
        recoveryAttemptedVideoID = nil
        isPlayingPreview = usePreview

        // Recorded on load rather than on first frame: a video that fails to resolve
        // was still something a person chose to watch, and history is more useful
        // for retracing that choice than for proving playback happened. A preview
        // clip isn't a watch, though. Fetch the record so playback position can be
        // restored from a previous watch.
        if !usePreview {
            historyContext?.recordWatch(video)
            fetchWatchedVideoForResume(video)
        }

        loadTask?.cancel()
        loadTask = Task {
            // Attempt to SharePlay this video if a FaceTime call is active.
            if presentation == .fullWindow {
                await coordinator.coordinatePlaybackOfVideo(video)
            }
            await resolveAndEnqueue(video, usePreview: usePreview, autoplay: autoplay,
                                    resumeTime: startTime)
        }

        // In visionOS, configure the spatial experience for either .inline or .fullWindow playback.
        configureAudioExperience(for: presentation)

        // Set the presentation, which typically presents the player full window.
        self.presentation = presentation
    }

    /// Resolves a media URL for the video and hands it to the player.
    /// - Parameter resumeTime: A position to open at instead of the saved watch
    ///   position — either where playback was when a stream failed mid-play, or a
    ///   moment the person picked from the scene thumbnails. Applied once the new
    ///   item reports itself ready.
    private func resolveAndEnqueue(_ video: Video, usePreview: Bool, autoplay: Bool, resumeTime: CMTime? = nil) async {
        isResolvingStream = true
        defer { isResolvingStream = false }

        let url: URL
        if usePreview, let previewURL = video.previewURL {
            url = previewURL
            currentHeight = nil
        } else {
            do {
                let stream = try await resolveStream(for: video)
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

        let playerItem = AVPlayerItem(asset: Self.asset(at: url, from: video.sourceID))
        applyQualityCeiling(to: playerItem)
        #if !os(macOS)
        playerItem.externalMetadata = await createMetadataItems(for: video)
        #endif
        player.replaceCurrentItem(with: playerItem)
        logger.debug("🍿 \(video.name) enqueued for playback.")

        // Observe the player item's status to seek to the saved playback position
        // once it's ready to play. This ensures the item is prepared before seeking.
        // A status of `.failed` is the other of the two signals `handlePlaybackFailure`
        // watches for — the notification-based one fires for a mid-stream failure,
        // this one catches a stream that never becomes playable in the first place.
        Task { @MainActor in
            for await status in playerItem.publisher(for: \.status).values {
                if status == .readyToPlay {
                    if let resumeTime {
                        _ = await player.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero)
                    } else {
                        seekToSavedPosition()
                    }
                }
                if status == .failed { handlePlaybackFailure(for: playerItem) }
                // Either outcome ends the watch: a failed item can never become
                // seekable, and leaving the loop running would keep it alive.
                if status != .unknown { break }
            }
        }

        if autoplay {
            player.play()
        }
    }

    /// Resolves a stream, falling back to the same video on another site.
    ///
    /// This is what deduplication buys. A merged feed knows that one scene exists on
    /// several sites — see ``VideoMatcher`` — so a site that has pulled the video,
    /// blocked the region, or simply broken is no longer the end of the attempt: the
    /// app asks the next site holding the same video. Only the site changes; what
    /// plays is what was tapped.
    ///
    /// The original error is what surfaces if every copy fails, since that's the one
    /// about the video the person actually chose.
    private func resolveStream(for video: Video) async throws -> StreamSource {
        do {
            return try await client.stream(for: video)
        } catch {
            for alternate in video.alternateIDs {
                guard !Task.isCancelled else { throw error }
                guard let stream = try? await client.stream(for: Video(id: alternate)) else { continue }
                logger.debug("↩︎ \(video.id) unavailable, playing the copy on \(alternate.sourceID)")
                return stream
            }
            throw error
        }
    }

    /// Builds an asset that identifies itself the way its site expects.
    ///
    /// The player fetches manifests and segments itself, and that stack sends none of
    /// the headers the app uses for pages. missav's media CDN answers 403 to a request
    /// without a referer, which surfaces as a stream that resolves cleanly and then
    /// fails the moment it's handed to the player — the manifest URL is fine, so it
    /// reads as a broken video rather than a rejected request.
    ///
    /// `AVURLAssetHTTPHeaderFieldsKey` isn't part of the documented API. The supported
    /// alternative is a resource-loader delegate, which for HLS means intercepting a
    /// custom scheme and re-serving every playlist and segment by hand. This app has no
    /// App Store path — see NOTICE.md — so the header key is the proportionate choice.
    static func asset(at url: URL, from sourceID: String) -> AVURLAsset {
        let headers = ContentSources.source(with: sourceID)?.playbackHeaders(for: url) ?? [:]
        guard !headers.isEmpty else { return AVURLAsset(url: url) }
        return AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    }

    /// Applies the person's Maximum Quality setting to an adaptive stream.
    ///
    /// For a fixed rendition the source already chose one, but an HLS manifest
    /// leaves the choice to the player — so without this the setting would appear
    /// to do nothing on sources that serve adaptive streams. A live choice made
    /// through the AVKit quality menu during this session takes priority over the
    /// profile setting, since it's the more recent expression of what the person wants.
    private func applyQualityCeiling(to item: AVPlayerItem) {
        if let sessionOverride = sessionQualityCeilingHeight {
            guard let height = sessionOverride else { return }
            item.preferredMaximumResolution = Self.resolution(forHeight: height)
            return
        }
        let quality = PlaybackSettings.maximumQuality
        guard quality != .auto else { return }
        item.preferredMaximumResolution = Self.resolution(forHeight: quality.ceiling)
    }

    /// Changes the quality ceiling for the video playing right now, and remembers the
    /// choice for every subsequent video loaded this session.
    ///
    /// This exists alongside the profile's Maximum Quality setting to let AVKit's
    /// quality menu switch resolution live, mid-stream, without waiting for the next
    /// video to load. `height` of `nil` selects Auto, removing any ceiling.
    func applyQualityCeiling(height: Int?) {
        sessionQualityCeilingHeight = height
        guard let item = player.currentItem else { return }
        if let height {
            item.preferredMaximumResolution = Self.resolution(forHeight: height)
            // AVKit gives no way to ask an adaptive stream what it's actually
            // rendering, so the chosen ceiling is the best available estimate —
            // the same approximation `currentHeight`'s doc comment already accepts.
            currentHeight = height
        } else {
            item.preferredMaximumResolution = .zero
            // Auto means genuinely unknown until the next stream resolves, rather
            // than a guess this app has no way to verify.
            currentHeight = nil
        }
    }

    /// The maximum resolution to hand `AVPlayerItem.preferredMaximumResolution` for a
    /// given height ceiling, assuming a 16:9 aspect ratio.
    private static func resolution(forHeight height: Int) -> CGSize {
        let height = Double(height)
        return CGSize(width: height * 16 / 9, height: height)
    }

    /// Handles a player item failure, reported either as `.status == .failed` or via
    /// the `AVPlayerItemFailedToPlayToEndTime` notification.
    ///
    /// This app's streams are signed URLs the source expires after a while, and an
    /// expired URL fails in exactly the way a genuinely broken video does — there's
    /// no error code that tells them apart. So the first failure for a video gets
    /// the benefit of the doubt: the app remembers the playback position, re-resolves
    /// a fresh stream the same way `loadVideo` does, and resumes from there. Only a
    /// second failure for the same video is treated as a real error.
    private func handlePlaybackFailure(for failedItem: AVPlayerItem?) {
        // Ignore a failure reported for an item that isn't current any more — it was
        // already superseded by a new load or a previous recovery attempt.
        guard let failedItem, failedItem === player.currentItem, let video = currentItem else { return }

        guard recoveryAttemptedVideoID != video.id else {
            loadError = failedItem.error?.localizedDescription
                ?? String(localized: "This video couldn’t be played.", comment: "A generic video playback error")
            return
        }
        recoveryAttemptedVideoID = video.id

        let resumeTime = player.currentTime()
        loadTask?.cancel()
        loadTask = Task {
            await resolveAndEnqueue(video, usePreview: isPlayingPreview, autoplay: true, resumeTime: resumeTime)
        }
    }

    /// Fetches and stores the watch history entry for a video so that playback position
    /// can be restored from a previous watch. Does nothing if history context is unavailable.
    private func fetchWatchedVideoForResume(_ video: Video) {
        guard let context = historyContext else { return }
        let sourceID = video.sourceID
        let itemID = video.itemID
        let descriptor = FetchDescriptor<WatchedVideo>(
            predicate: #Predicate { $0.sourceID == sourceID && $0.itemID == itemID }
        )
        if let existing = try? context.fetch(descriptor).first {
            currentWatchedVideo = existing
        }
    }

    /// Seeks to a saved playback position if one exists and meets resume criteria.
    /// Watches with a saved position are resumed from that point; videos without
    /// a saved position or those never seen before play from the beginning.
    ///
    /// The player must be ready to seek (player item status is `readyToPlay`).
    private func seekToSavedPosition() {
        guard let watched = currentWatchedVideo,
              let duration = player.currentItem?.duration,
              duration.isNumeric else { return }

        let position = watched.playbackPosition
        let durationSeconds = Int(duration.seconds)

        // Resume only if position is past the 30-second mark and not within 60 seconds
        // of the end. Skip resume if duration is zero (unknown) to avoid seeking beyond
        // the actual content length.
        guard position > 30 && (durationSeconds == 0 || position < durationSeconds - 60) else { return }

        let targetTime = CMTime(seconds: Double(position), preferredTimescale: 1000)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            // Seeking complete; playback will resume from the saved position.
        }
    }

    /// Clears any loaded media and resets the player model to its default state.
    /// Saves the final playback position before teardown so progress isn't lost.
    func reset() {
        loadTask?.cancel()
        loadTask = nil
        currentItem = nil
        loadError = nil
        currentHeight = nil
        isResolvingStream = false
        // Save the final position before clearing the watch entry, so the user's
        // place is preserved even if they navigate away mid-playback.
        updatePlaybackPosition()
        currentWatchedVideo = nil
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
        // Record the current playback position before pausing, so the user's place
        // is captured even if the app is backgrounded or the player is closed
        // before the periodic observer fires.
        updatePlaybackPosition()
        player.pause()
    }

    func togglePlayback() {
        player.timeControlStatus == .paused ? play() : pause()
    }

    // MARK: - Time Observation

    /// The timestamp of the last playback position update, used to throttle
    /// position recording to approximately every 10 seconds.
    @ObservationIgnored private var lastPositionUpdate: Date = Date.distantPast

    private func addTimeObserver() {
        removeTimeObserver()
        // Observe the player's timing once every second. The periodic observer updates
        // playback position and checks whether to propose the next video.
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
                    // Update playback position periodically (approximately every 10 seconds)
                    // to record the current playback location.
                    self.updatePlaybackPositionIfNeeded(time)
                }
            }
    }

    /// Updates the playback position in the watch history if at least 10 seconds have
    /// elapsed since the last update. This throttles writes to the history context.
    private func updatePlaybackPositionIfNeeded(_ time: CMTime) {
        let now = Date.now
        if now.timeIntervalSince(lastPositionUpdate) >= 10 {
            lastPositionUpdate = now
            updatePlaybackPosition(time)
        }
    }

    /// Records the current playback position into the watch history entry. If no watch
    /// entry exists or no time is available, this does nothing.
    private func updatePlaybackPosition(_ time: CMTime = .zero) {
        guard let watched = currentWatchedVideo, let context = historyContext else { return }
        let position = Int(time == .zero ? (player.currentTime().seconds) : time.seconds)
        watched.playbackPosition = max(0, position)
        try? context.save()
    }

    private func removeTimeObserver() {
        guard let timeObserver = timeObserver else { return }
        player.removeTimeObserver(timeObserver)
        self.timeObserver = nil
    }
}
