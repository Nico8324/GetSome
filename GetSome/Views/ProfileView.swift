/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The profile and settings screen.
*/

import SwiftUI
import SwiftData

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

    @State private var email = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var isSignedIn = false
    @State private var signedInAs: String?
    @State private var signInError: String?

    @AppStorage(ContentSources.primarySourceKey) private var primarySourceID = ContentSources.all[0].id
    @AppStorage(PlaybackSettings.maximumQualityKey) private var maximumQuality = StreamQuality.auto.rawValue
    @AppStorage("didConfirmAge") private var didConfirmAge = false

    /// Whether this screen was presented on top of something, rather than as a tab.
    var isModal = true

    @State private var isConfirmingRemoveAll = false
    @State private var didClearCache = false
    @State private var requestCount = 0

    /// Signs in, then clears the password from memory either way.
    ///
    /// The field is emptied on failure too: leaving a rejected password sitting in
    /// a view's state is the kind of thing that ends up in a screenshot.
    private func signIn(to account: any AuthenticatingSource) {
        isSigningIn = true
        signInError = nil
        let username = email
        let secret = password
        password = ""
        Task {
            do {
                try await SourceAuthenticator.shared.signIn(to: account, username: username, password: secret)
                isSignedIn = true
                signedInAs = username
                // The playlists become feeds, so fetch them before the picker is
                // next drawn rather than leaving the account looking empty.
                await ContentClient.shared.refreshPlaylists(for: account.id)
            } catch {
                signInError = error.localizedDescription
            }
            isSigningIn = false
        }
    }

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
                    Titles and keywords are sent to Google Translate to be translated. Text \
                    already in \(store.targetLanguageName) never leaves this device.
                    """ : """
                    Off, so titles and keywords stay in whatever language they were uploaded \
                    in. Turning this on sends them to Google Translate — the only part of this \
                    app that shares what you’re browsing.
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
            } header: {
                Text("Storage")
            } footer: {
                Text("Cached pages hold recently resolved video streams and posters.")
            }

            Section {
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
                        TextField("Email", text: $email)
                            #if !os(macOS)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            #endif
                        SecureField("Password", text: $password)
                            #if !os(macOS)
                            .textContentType(.password)
                            #endif
                        Button(isSigningIn ? "Signing In…" : "Sign In") {
                            signIn(to: account)
                        }
                        .disabled(email.isEmpty || password.isEmpty || isSigningIn)
                        if let signInError {
                            Text(signInError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("\(account.displayName) Account")
                } footer: {
                    Text(isSignedIn ? """
                        Your subscriptions and favorites appear as feeds in Browse. \
                        Signing out forgets the password stored on this device.
                        """ : """
                        Optional. Signing in adds your subscriptions and favorites as feeds. \
                        The password is kept in this device's keychain, sent only to \
                        \(account.displayName), and never written to Diagnostics.
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
        .task {
            requestCount = await RequestLog.shared.recent.count
            // A stored credential means signed in as far as this screen is
            // concerned; the session itself is restored lazily on first use.
            if let account = ContentSources.all.compactMap({ $0 as? any AuthenticatingSource }).first,
               let stored = CredentialStore.credential(for: account.id) {
                isSignedIn = true
                signedInAs = stored.username
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
