/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The profile and settings screen.
*/

import SwiftUI
import SwiftData
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif
import UniformTypeIdentifiers

/// The profile and settings screen.
///
/// The app has no accounts — everything a person builds up lives on their device —
/// so this screen is a place to see that state and change how the app behaves.
///
/// Settings that pick one of several values collapse to a single row showing the
/// current choice. Laid out flat, they filled the screen with radio buttons and
/// pushed everything else below the fold.
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(TranslationStore.self) private var translator

    @Query(sort: \SavedVideo.createdAt, order: .reverse)
    private var saved: [SavedVideo]

    @Query(sort: \WatchedVideo.watchedAt, order: .reverse)
    private var watched: [WatchedVideo]

    @State private var isSigningIn = false
    @State private var isSignedIn = false
    @State private var signedInAs: String?

    @AppStorage(ContentSources.primarySourceKey) private var primarySourceID = ContentSources.all[0].id
    @AppStorage(PlaybackSettings.maximumQualityKey) private var maximumQuality = StreamQuality.auto.rawValue
    @AppStorage("didConfirmAge") private var didConfirmAge = false
    @AppStorage("lockRequiresBiometrics") private var lockRequiresBiometrics = false

    /// Whether this screen was presented on top of something, rather than as a tab.
    var isModal = true

    @State private var isConfirmingRemoveAll = false
    @State private var didClearCache = false
    @State private var requestCount = 0
    @State private var biometricsAvailable = false

    #if !os(tvOS)
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var importSummary: String?
    #endif

    var body: some View {
        // @Bindable is the supported way to bind to an @Observable object held in
        // the environment. A hand-rolled Binding that reaches for the environment
        // in its setter runs after body has returned, where the value isn't valid.
        @Bindable var store = translator

        return List {
            header

            if ContentSources.hasMultipleSources {
                Section {
                    Picker("Default Site", selection: $primarySourceID) {
                        ForEach(ContentSources.all, id: \.id) { source in
                            Text(source.displayName).tag(source.id)
                        }
                    }
                    .settingsPickerStyle()
                } footer: {
                    Text("The site Watch Now leads with. Every site stays available in Browse.")
                }
            }

            Section {
                Picker("Maximum Quality", selection: $maximumQuality) {
                    ForEach(StreamQuality.allCases) { quality in
                        Text(quality.name).tag(quality.rawValue)
                    }
                }
                .settingsPickerStyle()
            } header: {
                Text("Playback")
            } footer: {
                Text("""
                    Applies the next time a video starts, and sites don’t always offer every \
                    resolution. Automatic uses up to \(StreamQuality.platformDefault)p on this device.
                    """)
            }

            Section {
                Toggle("Translate to \(store.targetLanguageName)", isOn: $store.isEnabled)

                // Status only matters once translation is on.
                if store.isEnabled {
                    if translator.isTranslating {
                        LabeledContent("Status") {
                            HStack(spacing: Constants.genreVerticalPadding) {
                                ProgressView().controlSize(.small)
                                Text("Translating…")
                            }
                        }
                    } else if let error = translator.lastError {
                        LabeledContent("Status") {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            } header: {
                Text("Language")
            } footer: {
                // Stated plainly in both states: this is the one feature that sends
                // anything about your browsing off the device.
                Text(store.isEnabled ? """
                    Titles in languages already downloaded to this device are translated on \
                    it — this app never downloads any. The rest are sent to Google Translate. \
                    Text already in \(store.targetLanguageName) never leaves this device. \
                    Keywords are search terms, so they stay as the site wrote them.
                    """ : """
                    Off, so titles stay in whatever language they were uploaded in. Turning \
                    this on translates them on this device where its languages are already \
                    downloaded, and through Google Translate otherwise.
                    """)
            }

            Section {
                LabeledContent("Saved Videos", value: saved.count.formatted())

                Button("Remove All Saved", role: .destructive) {
                    isConfirmingRemoveAll = true
                }
                .disabled(saved.isEmpty)

                Button(didClearCache ? "Cached Pages Cleared" : "Clear Cached Pages") {
                    Task {
                        await ContentClient.shared.clearCache()
                        didClearCache = true
                    }
                }
                .disabled(didClearCache)

                Button("Clear Saved Translations") {
                    translator.clearCache()
                }
                .disabled(translator.translations.isEmpty)

                #if !os(tvOS)
                Button("Export Saved Videos") {
                    isExporting = true
                }
                .disabled(saved.isEmpty)

                Button("Import Saved Videos") {
                    isImporting = true
                }
                #endif
            } header: {
                Text("Storage")
            } footer: {
                // Cached pages hold recently resolved video streams and posters.
                // Export and import let a person move their library to a new device
                // without needing iCloud.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cached pages hold recently resolved video streams and posters.")
                    // Guarded to match the state it reads: tvOS has no document
                    // picker, so it has neither the buttons nor their outcome.
                    #if !os(tvOS)
                    if let summary = importSummary {
                        Text(summary)
                            .foregroundStyle(.secondary)
                    }
                    #endif
                }
            }

            Section {
                if biometricsAvailable {
                    Toggle("Require Face ID", isOn: $lockRequiresBiometrics)
                }

                Button("Lock the App", role: .destructive) {
                    didConfirmAge = false
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Locking asks for age confirmation again before showing anything.")
            }

            if let account = ContentSources.all.compactMap({ $0 as? any AuthenticatingSource }).first {
                Section {
                    if isSignedIn {
                        LabeledContent("Signed in", value: signedInAs ?? account.displayName)
                        Button("Sign Out", role: .destructive) {
                            Task {
                                await SourceAuthenticator.shared.signOut(of: account)
                                AccountPlaylistStore.removePlaylists(for: account.id)
                                isSignedIn = false
                                signedInAs = nil
                            }
                        }
                    } else {
                        #if os(tvOS)
                        Text("Signing in needs a web browser, so it isn’t available here.")
                            .foregroundStyle(.secondary)
                        #else
                        Button("Sign In") { isSigningIn = true }
                        #endif
                    }
                } header: {
                    Text("\(account.displayName) Account")
                } footer: {
                    Text(isSignedIn ? """
                        Your playlists and liked videos appear as feeds in Browse. \
                        Signing out forgets the session kept on this device.
                        """ : """
                        Optional. Signing in adds your playlists and liked videos as feeds. \
                        You sign in on \(account.displayName)'s own page, so this app never \
                        sees your password — it keeps only the session that results.
                        """)
                }
            }

            Section {
                NavigationLink {
                    HistoryView()
                } label: {
                    LabeledContent("History", value: watched.count.formatted())
                }
            } footer: {
                Text("""
                    Kept by this app, across every site, and never sent anywhere. \
                    Clearing it is on that screen.
                    """)
            }

            Section {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    LabeledContent("Diagnostics", value: requestCount.formatted())
                }
            } footer: {
                Text("A record of recent requests, for reporting a feed that stopped working.")
            }

            Section("About") {
                LabeledContent("Version", value: Constants.appVersion)
                ForEach(ContentSources.all, id: \.id) { source in
                    Link(destination: source.homeURL) {
                        LabeledContent(source.displayName, value: source.homeURL.host() ?? "")
                    }
                }
            }
        }
        .navigationTitle("Profile")
        #if !os(tvOS)
        // Presented from the list rather than from inside the section, so the sheet
        // isn't torn down when the row it came from stops being drawn.
        .sheet(isPresented: $isSigningIn) {
            if let account = ContentSources.all.compactMap({ $0 as? any AuthenticatingSource }).first {
                SignInWebView(source: account) { cookies in
                    Task {
                        await SourceAuthenticator.shared.adopt(cookies: cookies, for: account)
                        isSignedIn = CredentialStore.hasSession(for: account.id)
                        // The playlists are feeds, so fetch them before the picker is
                        // next drawn rather than leaving the account looking empty.
                        await ContentClient.shared.refreshPlaylists(for: account.id)
                    }
                }
            }
        }
        #endif
        .task {
            #if canImport(LocalAuthentication)
            // Check if biometric authentication is available on this device.
            let context = LAContext()
            biometricsAvailable = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
            #endif
            // Left false where the framework doesn't exist, which hides the toggle.
        }
        .task {
            requestCount = await RequestLog.shared.recent.count
            // A stored credential means signed in as far as this screen is
            // concerned; the session itself is restored lazily on first use.
            if let account = ContentSources.all.compactMap({ $0 as? any AuthenticatingSource }).first {
                isSignedIn = CredentialStore.hasSession(for: account.id)
                signedInAs = CredentialStore.credential(for: account.id)?.username
            }
        }
        #if !os(tvOS)
        .toolbar {
            if isModal {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #endif
        .confirmationDialog(
            "Remove all saved videos?",
            isPresented: $isConfirmingRemoveAll,
            titleVisibility: .visible
        ) {
            Button("Remove All", role: .destructive) {
                for item in saved {
                    context.delete(item)
                }
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears \(saved.count) saved videos from this device. It can’t be undone.")
        }
        #if !os(tvOS)
        .fileExporter(
            isPresented: $isExporting,
            document: SavedExportDocument(saved: saved),
            contentType: .json,
            defaultFilename: "GetSome-Saved"
        ) { _ in
            // File written successfully.
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            onCompletion: { result in
                switch result {
                case .success(let url):
                    // Security-scoped resources need access granted before reading.
                    guard url.startAccessingSecurityScopedResource() else {
                        importSummary = "Unable to access the file."
                        return
                    }
                    defer { url.stopAccessingSecurityScopedResource() }

                    do {
                        let data = try Data(contentsOf: url)
                        let videos = try SavedVideo.importVideos(from: data)
                        // Only insert videos that aren’t already saved.
                        var imported = 0
                        for video in videos {
                            if context.savedVideo(for: video.id) == nil {
                                context.insert(SavedVideo(video: video))
                                imported += 1
                            }
                        }
                        try? context.save()
                        importSummary = imported == 1 ? "Imported 1 video." : "Imported \(imported) videos."
                    } catch {
                        importSummary = "Failed to import: \(error.localizedDescription)"
                    }
                case .failure:
                    importSummary = "Failed to select file."
                }
            }
        )
        #endif
    }

    private var header: some View {
        Section {
            HStack(spacing: Constants.verticalTextSpacing) {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.profileHeaderIconSize, height: Constants.profileHeaderIconSize)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading) {
                    Text("Guest")
                        .font(.title3.bold())
                    Text("No account. Everything stays on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, Constants.genreSpacing)
        }
    }
}

#if !os(tvOS)
/// A FileDocument that wraps SavedVideo export data for the file exporter.
private struct SavedExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var data: Data

    init(saved: [SavedVideo]) {
        // Encode the saved videos as JSON; this call should not throw in normal use.
        self.data = (try? SavedVideo.exportData(saved)) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw NSError(domain: "SavedExportDocument", code: 1)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif

extension View {
    /// Collapses a settings picker to one row showing the current value.
    func settingsPickerStyle() -> some View {
        #if os(macOS)
        self.pickerStyle(.menu)
        #else
        self.pickerStyle(.navigationLink)
        #endif
    }
}

#Preview(traits: .previewData) {
    NavigationStack {
        ProfileView()
    }
}
