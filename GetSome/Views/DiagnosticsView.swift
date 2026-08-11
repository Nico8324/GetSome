/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A record of recent requests, for reporting a problem that can't be reproduced.
*/

import SwiftUI

/// A record of recent requests, for reporting a problem that can't be reproduced.
///
/// This lives on its own screen rather than in the profile list: it's long, it's
/// rarely needed, and when it *is* needed the person is usually being asked to
/// find it by someone else.
struct DiagnosticsView: View {
    @State private var requests = [RequestRecord]()
    @State private var file: URL?
    @State private var isPreparing = false

    private var driftCount: Int {
        requests.filter(\.isSuspectedDrift).count
    }

    var body: some View {
        List {
            if driftCount > 0 {
                Section {
                    Label("\(driftCount) request(s) returned a page this app didn’t recognise",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } footer: {
                    Text("""
                        That usually means the site changed its layout rather than that \
                        anything is wrong here. Sharing this report includes the page itself.
                        """)
                }
            }

            Section {
                #if !os(tvOS)
                if let file {
                    ShareLink(item: file) {
                        Label("Share Report", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        isPreparing = true
                        Task {
                            file = await RequestLog.shared.writeReport(appVersion: Constants.appVersion)
                            isPreparing = false
                        }
                    } label: {
                        LabeledContent("Prepare Report") {
                            if isPreparing { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(isPreparing)
                }
                #endif

                Button("Clear", role: .destructive) {
                    Task {
                        await RequestLog.shared.clear()
                        requests = []
                        file = nil
                    }
                }
                .disabled(requests.isEmpty)
            } footer: {
                Text("The report lists what the app asked each site for and what came back.")
            }

            Section("Recent Requests") {
                if requests.isEmpty {
                    Text("Nothing recorded yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(requests) { record in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.summary)
                                .font(.footnote)
                            Text(record.url.absoluteString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(record.isSuspectedDrift ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
        .task {
            requests = await RequestLog.shared.recent
        }
    }
}

#Preview(traits: .previewData) {
    NavigationStack {
        DiagnosticsView()
    }
}
