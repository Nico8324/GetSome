/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The top level tab navigation for the app.
*/

import SwiftUI

/// The top level tab navigation for the app.
struct GetSomeTabs: View {
    /// Keep track of tab view customizations in app storage.
    #if !os(macOS) && !os(tvOS)
    @AppStorage("sidebarCustomizations") var tabViewCustomization: TabViewCustomization
    #endif
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Namespace private var namespace
    @State private var selectedTab: Tabs = .watchNow

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(Tabs.watchNow.name, systemImage: Tabs.watchNow.symbol, value: .watchNow) {
                WatchNowView()
            }
            .customizationID(Tabs.watchNow.customizationID)
            // Disable customization behavior on the watchNow tab to ensure that the tab remains visible.
            #if !os(macOS) && !os(tvOS)
            .customizationBehavior(.disabled, for: .sidebar, .tabBar)
            #endif

            Tab(Tabs.browse.name, systemImage: Tabs.browse.symbol, value: .browse) {
                BrowseView()
            }
            .customizationID(Tabs.browse.customizationID)
            // Disable customization behavior on the browse tab to ensure that the tab remains visible.
            #if !os(macOS) && !os(tvOS)
            .customizationBehavior(.disabled, for: .sidebar, .tabBar)
            #endif

            Tab(Tabs.saved.name, systemImage: Tabs.saved.symbol, value: .saved) {
                SavedView()
            }
            .customizationID(Tabs.saved.customizationID)

            Tab(value: .search, role: .search) {
                SearchView()
            }
            .customizationID(Tabs.search.customizationID)
            #if !os(macOS) && !os(tvOS)
            .customizationBehavior(.disabled, for: .sidebar, .tabBar)
            #endif

            #if os(tvOS)
            // tvOS has no navigation bar for a profile button, so the screen
            // gets a tab of its own.
            Tab(Tabs.profile.name, systemImage: Tabs.profile.symbol, value: .profile) {
                NavigationStack {
                    ProfileView(isModal: false)
                }
            }
            .customizationID(Tabs.profile.customizationID)
            #endif

            #if !os(visionOS)
            // Present every source's feeds, grouped the same way regardless of how
            // many sites the app browses.
            ForEach(FeedGroup.navigableGroups, id: \.self) { group in
                let feeds = ContentSources.feeds(in: group)
                if !feeds.isEmpty {
                    TabSection {
                        ForEach(feeds) { feed in
                            Tab(feed.qualifiedName, systemImage: feed.icon, value: Tabs.feed(feed)) {
                                FeedView(feed: feed, namespace: namespace)
                            }
                            .customizationID(Tabs.feed(feed).customizationID)
                        }
                    } header: {
                        Label(group.sectionTitle, systemImage: group.sectionIcon)
                    }
                    .customizationID("com.getsome.GetSome.section." + group.rawValue)
                    #if !os(macOS) && !os(tvOS)
                    // Prevent the section from appearing in the tab bar by default.
                    .defaultVisibility(.hidden, for: .tabBar)
                    .hidden(horizontalSizeClass == .compact)
                    #endif
                }
            }
            #endif
        }
        .tabViewStyle(.sidebarAdaptable)
        #if !os(macOS) && !os(tvOS)
        .tabViewCustomization($tabViewCustomization)
        #endif
    }
}

#Preview(traits: .previewData) {
    GetSomeTabs()
}
