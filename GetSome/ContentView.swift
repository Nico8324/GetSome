/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app's top level view.
*/

import SwiftUI
#if os(iOS) || os(macOS)
import Translation
#endif

/// A view that presents the app's user interface.
struct ContentView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(TranslationStore.self) private var translator
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
        // Translating needs no hosting — the store builds its own session. This
        // task exists only so the system can present its language-download UI,
        // which a directly built session isn't allowed to request.
        #if os(iOS) || os(macOS)
        // @Sendable so the closure doesn't inherit this view's main actor
        // isolation: TranslationSession isn't Sendable and has to stay put.
        .translationTask(translator.downloadConfiguration) { @Sendable session in
            await translator.completeDownload(using: session)
        }
        #endif
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
