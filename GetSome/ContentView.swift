/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app's top level view.
*/

import SwiftUI
import SwiftData
#if canImport(Translation)
import Translation
#endif

/// A view that presents the app's user interface.
struct ContentView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    #if os(visionOS)
    @Environment(ImmersiveEnvironment.self) private var immersiveEnvironment
    #endif

    /// A Boolean value that indicates whether a person confirmed they're old enough to view the content.
    @AppStorage("didConfirmAge") private var didConfirmAge = false

    /// Whether the user has opted to require biometric authentication.
    @AppStorage("lockRequiresBiometrics") private var lockRequiresBiometrics = false

    /// Whether the app is currently locked pending biometric authentication.
    ///
    /// The app is locked when it transitions to the background and biometric lock is enabled.
    @State private var isLocked = true

    var body: some View {
        Group {
            if didConfirmAge && lockRequiresBiometrics && isLocked {
                // If biometric lock is enabled and engaged, show the lock screen instead
                // of the library. The age gate flow remains untouched.
                AppLockView {
                    isLocked = false
                }
            } else if didConfirmAge {
                library
            } else {
                AgeGateView { didConfirmAge = true }
            }
        }
        #if canImport(Translation)
        // The bridge that makes on-device translation possible: the framework only
        // vends sessions through this modifier, so SystemTranslator publishes the
        // configuration it needs and receives its session here. See SystemTranslator.
        .translationTask(SystemTranslator.shared.configuration) { session in
            guard let batch = await SystemTranslator.shared.takeWork() else { return }
            await SystemTranslator.finish(.init(session: session), batch: batch)
        }
        #endif
        // The app switcher keeps a screenshot of the app. Display a privacy cover when
        // the app is backgrounded, so the snapshot shows an opaque screen with nothing sensitive.
        .overlay(alignment: .center) {
            if scenePhase != .active {
                Rectangle()
                    .fill(.black)
                    .overlay {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                    }
                    .ignoresSafeArea()
            }
        }
        // The player records watch history, but it's created before the model
        // container exists, so it's handed the context once there is one.
        .task {
            player.historyContext = context
            // Playlists are feeds, and feeds are read synchronously — so the list is
            // refreshed here, in the background, rather than when the picker draws.
            //
            // In an unstructured Task on purpose: this `.task` belongs to a Group
            // whose content swaps when the age gate clears, and the refresh was being
            // cancelled mid-request every launch — silently, since a cancelled await
            // never reaches the catch that would have reported it.
            Task {
                for source in ContentSources.all where CredentialStore.hasCredential(for: source.id) {
                    await ContentClient.shared.refreshPlaylists(for: source.id)
                }
            }
        }
        // When the app transitions to the background and biometric lock is enabled,
        // re-lock for the next foreground.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && lockRequiresBiometrics {
                isLocked = true
            }
        }
    }

    @ViewBuilder
    private var library: some View {
        #if os(visionOS)
        switch player.presentation {
        case .fullWindow:
            PlayerView()
                .immersiveEnvironmentPicker {
                    ImmersiveEnvironmentPickerView()
                }
                .onAppear {
                    player.play()
                }
        default:
            // Shows the app's content library by default.
            GetSomeTabs()
        }
        #else
        GetSomeTabs()
            .presentVideoPlayer()
        #endif
    }
}

#Preview(traits: .previewData) {
    ContentView()
}
