/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The main app structure.
*/

import SwiftUI
import SwiftData
import os

/// The main app structure.
@main
struct GetSomeApp: App {
    #if os(iOS)
    /// Answers UIKit's question about which orientations the app allows, so the
    /// full-window player can rotate while the browsing screens stay portrait.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    /// An object that manages the model storage configuration.
    private let modelContainer: ModelContainer

    /// An object that controls the video playback behavior.
    @State private var player = PlayerModel()

    /// An object that loads the video feeds the app presents.
    @State private var feeds = FeedStore()

    /// An object that translates the text sources publish.
    @State private var translator = TranslationStore()

    #if os(visionOS)
    /// An object that stores the app's level of immersion.
    @State private var immersiveEnvironment = ImmersiveEnvironment()
    /// The content brightness to apply to the immersive space.
    @State private var contentBrightness: ImmersiveContentBrightness = .automatic
    /// The effect modifies the passthrough in immersive space.
    @State private var surroundingsEffect: SurroundingsEffect? = nil
    #endif

    var body: some Scene {
        // The app's primary content window.
        WindowGroup {
            ContentView()
                .environment(player)
                .environment(feeds)
                .environment(translator)
                .modelContainer(modelContainer)
                #if os(visionOS)
                .environment(immersiveEnvironment)
                #endif
                #if os(macOS)
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                #endif
                // Set minimum window size
                #if os(macOS) || os(visionOS)
                .frame(minWidth: Constants.contentWindowWidth, maxWidth: .infinity, minHeight: Constants.contentWindowHeight, maxHeight: .infinity)
                #endif
                // Use a dark color scheme on supported platforms.
                #if os(iOS) || os(macOS)
                .preferredColorScheme(.dark)
                #endif
        }
        #if !os(tvOS)
        .windowResizability(.contentSize)
        #endif

        // The video player window
        #if os(macOS)
        PlayerWindow(player: player)
        #endif

        #if os(visionOS)
        // Defines an immersive space to present a destination in which to watch the video.
        ImmersiveSpace(id: ImmersiveEnvironmentView.id) {
            ImmersiveEnvironmentView()
                .environment(immersiveEnvironment)
                .onAppear {
                    immersiveEnvironment.immersiveSpaceState = .open
                    contentBrightness = immersiveEnvironment.contentBrightness
                    surroundingsEffect = immersiveEnvironment.surroundingsEffect
                }
                .onDisappear {
                    immersiveEnvironment.immersiveSpaceState = .closed
                    contentBrightness = .automatic
                    surroundingsEffect = nil
                }
            // Apply a custom tint color for the video passthrough of a person's hands and surroundings.
                .preferredSurroundingsEffect(surroundingsEffect)
        }
        // Set the content brightness for the immersive space.
        .immersiveContentBrightness(contentBrightness)
        // Set the immersion style to progressive, so the user can use the Digital Crown to dial in their experience.
        .immersionStyle(selection: .constant(.progressive), in: .progressive)
        #endif
    }

    /// Initializes the storage for the videos a person saves.
    init() {
        do {
            self.modelContainer = try ModelContainer(for: SavedVideo.self)
        } catch {
            // The saved-video schema is still moving as sources are added. Rather
            // than refusing to launch on a store SwiftData can't migrate, start
            // over: the only thing lost is a list the app can rebuild by hand.
            logger.error("Unable to open the saved-video store: \(error.localizedDescription)")
            do {
                self.modelContainer = try Self.makeFreshContainer()
            } catch {
                fatalError("Unable to create a saved-video store: \(error.localizedDescription)")
            }
        }
    }

    /// Deletes the existing store and creates an empty one.
    private static func makeFreshContainer() throws -> ModelContainer {
        let url = URL.applicationSupportDirectory.appending(path: "default.store")
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(filePath: url.path() + suffix))
        }
        return try ModelContainer(for: SavedVideo.self)
    }
}

/// A global log of events for the app.
let logger = Logger(subsystem: "com.getsome.GetSome", category: "App")
