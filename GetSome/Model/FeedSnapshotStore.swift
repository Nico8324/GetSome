/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A store that persists and restores feed snapshots to launch quickly with cached content.
*/

import Foundation

/// A store for persisting video snapshots from feeds across app launches.
///
/// Feed snapshots are cached on disk so the app can display content immediately on launch,
/// before network requests complete. Snapshots capture the initial page of each feed, allowing
/// users to see familiar content while fresh data loads in the background.
enum FeedSnapshotStore {
    /// Loads feed snapshots from the caches directory.
    ///
    /// Returns a dictionary mapping feed identifiers to their cached video arrays.
    /// If the snapshot file does not exist or cannot be decoded, returns an empty dictionary.
    static func load() -> [String: [Video]] {
        guard let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return [:]
        }

        let snapshotURL = cachesURL.appendingPathComponent("FeedSnapshots.json")

        guard let data = try? Data(contentsOf: snapshotURL) else {
            return [:]
        }

        let decoder = JSONDecoder()
        if let snapshots = try? decoder.decode([String: [Video]].self, from: data) {
            return snapshots
        }

        return [:]
    }

    /// Persists feed snapshots to the caches directory.
    ///
    /// Writes snapshots to an atomic temporary file, then moves it into place. If any error occurs,
    /// the operation is silently ignored because snapshot persistence is a cache, never critical.
    static func save(_ snapshots: [String: [Video]]) {
        guard let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }

        let snapshotURL = cachesURL.appendingPathComponent("FeedSnapshots.json")

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(snapshots) else {
            return
        }

        let tempURL = snapshotURL.appendingPathExtension("tmp")

        _ = try? data.write(to: tempURL, options: .atomic)
        _ = try? FileManager.default.replaceItemAt(snapshotURL, withItemAt: tempURL)
    }
}
