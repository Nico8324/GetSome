/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app's top level view.
*/

import SwiftUI
import SwiftData

/// A view that presents the app's user interface.
struct ContentView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.modelContext) private var context
    #if os(visionOS)
    @Environment(ImmersiveEnvironment.self) private var immersiveEnvironment
    #endif

    /// A Boolean value that indicates whether a person confirmed they're old enough to view the content.
    @AppStorage("didConfirmAge") private var didConfirmAge = false

    var body: some View {
        Group {
            if didConfirmAge {
                library
            } else {
                AgeGateView { didConfirmAge = true }
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
