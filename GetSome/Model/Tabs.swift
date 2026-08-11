/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A description of the tabs that the app can present.
*/

import SwiftUI

/// A description of the tabs that the app can present.
enum Tabs: Equatable, Hashable, Identifiable {
    case watchNow
    case browse
    case saved
    case search
    case profile
    /// A tab that presents one of a source's feeds.
    case feed(Feed)

    var id: String {
        switch self {
        case .watchNow: "watchNow"
        case .browse: "browse"
        case .saved: "saved"
        case .search: "search"
        case .profile: "profile"
        case .feed(let feed): feed.id
        }
    }

    var name: String {
        switch self {
        case .watchNow: String(localized: "Watch Now", comment: "Tab title")
        case .browse: String(localized: "Browse", comment: "Tab title")
        case .saved: String(localized: "Saved", comment: "Tab title")
        case .search: String(localized: "Search", comment: "Tab title")
        case .profile: String(localized: "Profile", comment: "Tab title")
        case .feed(let feed): feed.qualifiedName
        }
    }

    var customizationID: String {
        "com.getsome.GetSome." + id
    }

    var symbol: String {
        switch self {
        case .watchNow: "play"
        case .browse: "square.grid.2x2"
        case .saved: "heart"
        case .search: "magnifyingglass"
        case .profile: "person.crop.circle"
        case .feed(let feed): feed.icon
        }
    }

    var isSecondary: Bool {
        switch self {
        case .watchNow, .browse, .saved, .search, .profile: false
        case .feed: true
        }
    }
}

extension FeedGroup {
    /// The title of the sidebar section that presents this group.
    var sectionTitle: String {
        switch self {
        case .collection: String(localized: "Collections", comment: "Sidebar section title")
        case .chart: String(localized: "Charts", comment: "Sidebar section title")
        case .category: String(localized: "Categories", comment: "Sidebar section title")
        }
    }

    var sectionIcon: String {
        switch self {
        case .collection: "folder"
        case .chart: "chart.bar"
        case .category: "tag"
        }
    }
}
