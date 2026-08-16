/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Custom view modifiers that the app defines.
*/

import SwiftUI

extension View {
    #if !os(visionOS)
    // Only used in iOS and tvOS for full-window modal presentation.
    func presentVideoPlayer() -> some View {
        #if os(macOS)
        self.modifier(OpenVideoPlayerModifier())
        #else
        self.modifier(FullScreenCoverModifier())
        #endif
    }
    #endif

    func navigationDestinationVideo(in namespace: Namespace.ID) -> some View {
        self.modifier(NavigationDestinationVideo(namespace: namespace))
    }

    func transitionSource(id: some Hashable, namespace: Namespace.ID) -> some View {
        self.modifier(TransitionSourceModifier(id: AnyHashable(id), namespace: namespace))
    }
}

#if !os(macOS)
private struct FullScreenCoverModifier: ViewModifier {
    @Environment(PlayerModel.self) private var player
    @State private var isPresentingPlayer = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresentingPlayer) {
                PlayerView()
                    .onDisappear {
                        player.reset()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
            // Observe the player's presentation property.
            .onChange(of: player.presentation, { _, newPresentation in
                isPresentingPlayer = newPresentation == .fullWindow
            })
    }
}
#endif

private struct NavigationDestinationVideo: ViewModifier {
    @Environment(FeedStore.self) private var feeds
    var namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: NavigationNode.self) { node in
                switch node {
                case .feed(let id):
                    if let feed = ContentSources.feed(with: id) {
                        FeedView(
                            feed: feed,
                            namespace: namespace,
                            navigationPath: [NavigationNode.feed(id)])
                            #if os(iOS)
                            .toolbarRole(.editor)
                            .navigationTransition(.zoom(sourceID: AnyHashable(feed.id), in: namespace))
                            #endif
                    } else {
                        ContentUnavailableView("This collection isn’t available", systemImage: "list.and.film")
                    }

                case .video(let id):
                    // The video may come from a feed the app has loaded, or from a
                    // detail page that linked to it. The detail view fills in the rest.
                    DetailView(video: feeds.video(with: id) ?? Video(id: id))
                        #if os(iOS)
                        .toolbarRole(.editor)
                        .navigationTransition(.zoom(sourceID: AnyHashable(id), in: namespace))
                        #endif

                case .categories(let sourceID):
                    CategoriesView(sourceID: sourceID, namespace: namespace)
                        #if os(iOS)
                        .toolbarRole(.editor)
                        #endif

                case .keywords:
                    KeywordsView(namespace: namespace)
                        #if os(iOS)
                        .toolbarRole(.editor)
                        #endif

                case .tag(let sourceID, let keyword):
                    SearchResultsView(sourceID: sourceID, query: keyword, namespace: namespace)
                        #if os(iOS)
                        .toolbarRole(.editor)
                        #endif
                }
            }
    }
}

private struct TransitionSourceModifier: ViewModifier {
    var id: AnyHashable
    var namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .matchedTransitionSource(id: id, in: namespace) { src in
                src
                    .clipShape(.rect(cornerRadius: 10.0))
                    .shadow(radius: 12.0)
                    .background(.black)
            }
            #endif
    }
}

#if os(macOS)
private struct OpenVideoPlayerModifier: ViewModifier {
    @Environment(PlayerModel.self) private var player
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onChange(of: player.presentation, { oldValue, newValue in
                if newValue == .fullWindow {
                    openWindow(id: PlayerView.identifier)
                }
            })
    }
}
#endif
