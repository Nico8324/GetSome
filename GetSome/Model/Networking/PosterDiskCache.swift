/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Caches poster images on disk, persisting them across app launches.
*/

import CryptoKit
import Foundation

/// Stores poster images on disk for reuse across app launches.
///
/// Posters are cached in the app's caches directory, with filenames derived from
/// the image URL using SHA-256 hashing. The cache is managed by file count — excess
/// files are pruned by modification date — rather than by size, making the policy
/// transparent and predictable.
enum PosterDiskCache {
    /// The directory where poster files are stored.
    private static var postersDirectory: URL? {
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return caches.appendingPathComponent("Posters", isDirectory: true)
    }

    /// Returns the poster data for the specified URL, if cached.
    static func data(for url: URL) -> Data? {
        guard let fileURL = fileURL(for: url) else { return nil }
        return try? Data(contentsOf: fileURL)
    }

    /// Stores poster data on disk for the specified URL.
    ///
    /// Creates the posters directory as needed. Write failures are silently ignored —
    /// a cache is a best-effort optimization, never a requirement.
    static func store(_ data: Data, for url: URL) {
        guard let cacheDir = postersDirectory else { return }
        do {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            guard let fileURL = fileURL(for: url) else { return }
            try data.write(to: fileURL)
        } catch {
            // Disk cache failures are not fatal.
        }
    }

    /// Removes all cached posters.
    static func removeAll() {
        guard let cacheDir = postersDirectory else { return }
        try? FileManager.default.removeItem(at: cacheDir)
    }

    /// Deletes the oldest posters until the cache contains at most `limit` files.
    ///
    /// Pruning is triggered periodically to prevent unbounded cache growth. Files are
    /// removed in order of oldest modification date first.
    static func prune(keeping limit: Int = 600) {
        guard let cacheDir = postersDirectory else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        guard files.count > limit else { return }

        var filesByDate: [(url: URL, date: Date)] = []
        for fileURL in files {
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date = values.contentModificationDate else {
                continue
            }
            filesByDate.append((fileURL, date))
        }

        let sorted = filesByDate.sorted { $0.date < $1.date }
        let toRemove = sorted.count - limit
        for i in 0..<toRemove {
            try? FileManager.default.removeItem(at: sorted[i].url)
        }
    }

    /// The filename for the poster at the given URL.
    private static func fileURL(for url: URL) -> URL? {
        guard let cacheDir = postersDirectory else { return nil }
        let digest = SHA256.hash(data: url.absoluteString.data(using: .utf8) ?? Data())
        let hexString = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent("\(hexString).img")
    }
}
