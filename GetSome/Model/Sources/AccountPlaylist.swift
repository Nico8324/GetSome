/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The playlists a signed-in person keeps on a site.
*/

import Foundation

/// One playlist belonging to a signed-in person.
struct AccountPlaylist: Sendable, Hashable, Codable {
    let id: String
    let name: String
    let videoCount: Int
}

/// Remembers the playlists a site reported, so they can be offered as feeds.
///
/// ``ContentSource/feeds`` is synchronous — a picker can't wait on the network to
/// know what to draw — but playlists are only knowable from a request. Caching the
/// last answer bridges that: the feeds appear immediately on later launches and are
/// refreshed in the background.
///
/// Names, not contents. What a person called a playlist is the least of what the
/// account holds, and nothing here leaves the device.
enum AccountPlaylistStore {
    /// The playlists last seen for a source.
    static func playlists(for sourceID: String) -> [AccountPlaylist] {
        guard let data = UserDefaults.standard.data(forKey: key(sourceID)),
              let stored = try? JSONDecoder().decode([AccountPlaylist].self, from: data) else {
            return []
        }
        return stored
    }

    /// Replaces the playlists remembered for a source.
    static func setPlaylists(_ playlists: [AccountPlaylist], for sourceID: String) {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        UserDefaults.standard.set(data, forKey: key(sourceID))
    }

    /// Forgets a source's playlists. Called on sign-out, with the credential.
    static func removePlaylists(for sourceID: String) {
        UserDefaults.standard.removeObject(forKey: key(sourceID))
    }

    private static func key(_ sourceID: String) -> String { "accountPlaylists.\(sourceID)" }
}
