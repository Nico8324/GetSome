/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A record of recent requests, so a failure can be reported without reproducing it.
*/

import Foundation

/// What happened on one request to a source.
struct RequestRecord: Sendable, Identifiable {
    let id = UUID()
    var sourceID: String
    /// What the app was trying to do, such as a feed name or a search.
    var intent: String
    var url: URL
    var statusCode: Int?
    var byteCount: Int
    /// How many videos the source's parser found. `nil` for non-listing requests.
    var parsedCount: Int?
    var failure: String?
    var date: Date

    /// A Boolean value that indicates whether this looks like markup drift:
    /// the site answered normally, but the parser recognized nothing.
    var isSuspectedDrift: Bool {
        statusCode == 200 && parsedCount == 0
    }

    var summary: String {
        var parts = ["\(sourceID) · \(intent)"]
        parts.append(statusCode.map { "HTTP \($0)" } ?? "no response")
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
        if let parsedCount { parts.append("\(parsedCount) parsed") }
        if let failure { parts.append(failure) }
        return parts.joined(separator: " · ")
    }
}

/// A rolling record of recent requests, plus the last page that failed to parse.
///
/// The point is remote diagnosis. A scraper breaks when a site changes its markup,
/// and that happens to people in places you can't reach — a region you can't load,
/// a language you don't read, a feed that's empty only for them. Keeping the last
/// failing page means the person hitting the bug can hand you the exact bytes, and
/// you can replay them through the real parser offline.
actor RequestLog {
    static let shared = RequestLog()

    private var records = [RequestRecord]()
    private let limit = 40

    /// The most recent response whose parser found nothing, kept for export.
    private var failingPage: (record: RequestRecord, body: Data)?

    /// The largest body worth keeping. Listing pages run a few hundred kilobytes.
    private let maximumBodyBytes = 2_000_000

    func record(_ record: RequestRecord, body: Data? = nil) {
        records.append(record)
        if records.count > limit {
            records.removeFirst(records.count - limit)
        }
        if record.isSuspectedDrift, let body, body.count <= maximumBodyBytes {
            failingPage = (record, body)
        }
    }

    var recent: [RequestRecord] {
        records.reversed()
    }

    var hasFailingPage: Bool {
        failingPage != nil
    }

    func clear() {
        records.removeAll()
        failingPage = nil
    }

    /// A plain-text report describing recent requests.
    func report(appVersion: String) -> String {
        var lines = [
            "GetSome diagnostics",
            "app: \(appVersion)",
            "sources: " + ContentSources.all.map(\.id).joined(separator: ", "),
            "recorded: \(records.count) request(s)",
            ""
        ]
        for record in records.reversed() {
            lines.append("\(record.date.formatted(.iso8601)) \(record.summary)")
            lines.append("  \(record.url.absoluteString)")
        }
        if let failingPage {
            lines.append("")
            lines.append("--- last page the parser found nothing in ---")
            lines.append(failingPage.record.url.absoluteString)
            lines.append(String(data: failingPage.body, encoding: .utf8)
                ?? "(\(failingPage.body.count) bytes, not UTF-8)")
        }
        return lines.joined(separator: "\n")
    }

    /// Writes the report to a file and returns it, ready to share.
    func writeReport(appVersion: String) -> URL? {
        let text = report(appVersion: appVersion)
        let url = URL.temporaryDirectory.appending(path: "GetSome-diagnostics.txt")
        guard let data = text.data(using: .utf8), (try? data.write(to: url, options: .atomic)) != nil else {
            return nil
        }
        return url
    }
}
