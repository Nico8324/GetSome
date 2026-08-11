/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Translates the text that sources publish into the language of the device.
*/

import Foundation
import NaturalLanguage
import SwiftUI

// The Translation framework is unavailable on tvOS and visionOS, so every use of
// it is behind this condition.
#if os(iOS) || os(macOS)
import Translation
#endif

/// Translates the text that sources publish into the language of the device.
///
/// Sites publish titles and keywords in whatever language they were uploaded in —
/// often several within one listing. This object collects that text, groups it by
/// the language it appears to be written in, and translates each group on device
/// with Apple's Translation framework. Nothing leaves the device, and results are
/// cached so a title is only ever translated once.
///
/// Views ask for text through ``text(for:)``, which answers immediately with the
/// original and swaps in a translation when one arrives.
@MainActor
@Observable
final class TranslationStore {
    /// The user defaults key that holds whether translation is on.
    static let isEnabledKey = "translateSiteText"

    /// The user defaults key that holds whether the app asks to download languages.
    static let automaticDownloadKey = "downloadTranslationLanguagesAutomatically"

    /// The user defaults key that holds the languages already asked about.
    private static let askedLanguagesKey = "askedTranslationLanguages"

    /// Whether the app translates the text sources publish.
    ///
    /// Off until asked for. Translating means downloading a language model per
    /// language, which costs real disk space, so the app doesn't decide that on
    /// someone's behalf — and while it's off nothing is detected, queued, or
    /// prompted for.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.isEnabledKey)
            if isEnabled {
                lastError = nil
                enqueueEverythingSeen()
                scheduleFlush()
            } else {
                #if os(iOS) || os(macOS)
                downloadConfiguration = nil
                #endif
            }
        }
    }

    /// The language to translate into.
    let targetLanguage: Locale.Language

    /// A Boolean value that indicates whether this platform can translate at all.
    let isSupported: Bool

    /// Translations of site text, keyed by the original.
    ///
    /// Written a batch at a time so a page of cards redraws once per batch rather
    /// than once per title.
    private(set) var translations = [String: String]()

    /// Whether the app offers to download a language the moment it needs one.
    ///
    /// The download itself always needs a person's confirmation — the framework
    /// gives no way to fetch a language silently — but with this on, the app raises
    /// that request at the moment it hits the language, rather than leaving it
    /// buried in settings. Each language is asked about once, ever.
    var downloadsAutomatically: Bool {
        didSet { UserDefaults.standard.set(downloadsAutomatically, forKey: Self.automaticDownloadKey) }
    }

    /// Languages the app has text for but that aren't downloaded yet.
    private(set) var languagesNeedingDownload = Set<String>()

    /// A Boolean value that indicates whether a batch is in flight.
    private(set) var isTranslating = false

    /// Why the last attempt failed, if it did.
    ///
    /// Worth surfacing rather than swallowing: on the Simulator the framework
    /// refuses outright, and without this the app just quietly never translates.
    private(set) var lastError: String?

    #if os(iOS) || os(macOS)
    /// Drives the one translation task `ContentView` still hosts, which exists
    /// only to present the system's language-download UI.
    private(set) var downloadConfiguration: TranslationSession.Configuration?
    #endif

    /// Text waiting to be translated, grouped by the language it appears to be in.
    ///
    /// Deliberately not observed: views add to this while their bodies run, and
    /// that must not invalidate the view that's drawing.
    @ObservationIgnored private var pending = [String: Set<String>]()

    /// Text the app has already given up on, so it doesn't retry every redraw.
    @ObservationIgnored private var skipped = Set<String>()

    /// Text views have asked about, newest last, so switching translation on can
    /// act on what's already visible.
    @ObservationIgnored private var seenOrder = [String]()
    @ObservationIgnored private var recentlySeen = Set<String>()
    @ObservationIgnored private let seenLimit = 600

    /// Language pairs already checked with the system, so each is asked once.
    @ObservationIgnored private var availability = [String: Bool]()

    /// Languages the app has already asked to download, so it never nags twice.
    @ObservationIgnored private var askedLanguages: Set<String>

    /// At most one download request per launch, however many languages appear.
    @ObservationIgnored private var didRequestDownloadThisSession = false

    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private let cache: TranslationCache

    init(targetLanguage: Locale.Language = Locale.current.language) {
        self.targetLanguage = targetLanguage
        #if os(iOS) || os(macOS)
        self.isSupported = true
        #else
        self.isSupported = false
        #endif
        self.isEnabled = UserDefaults.standard.object(forKey: Self.isEnabledKey) as? Bool ?? false
        self.downloadsAutomatically =
            UserDefaults.standard.object(forKey: Self.automaticDownloadKey) as? Bool ?? true
        self.askedLanguages = Set(UserDefaults.standard.stringArray(forKey: Self.askedLanguagesKey) ?? [])
        self.cache = TranslationCache(language: targetLanguage.minimalIdentifier)
        self.translations = cache.load()
    }

    /// The name of the target language, for the profile screen.
    var targetLanguageName: String {
        Locale.current.localizedString(forIdentifier: targetLanguage.minimalIdentifier)
            ?? targetLanguage.minimalIdentifier
    }

    /// The name of a language code, for the profile screen.
    nonisolated func name(of languageCode: String) -> String {
        Locale.current.localizedString(forLanguageCode: languageCode) ?? languageCode
    }

    /// The languages waiting on a download, named and in a stable order.
    var missingLanguageNames: [String] {
        languagesNeedingDownload.map(name(of:)).sorted()
    }

    // MARK: - Asking for text

    /// Returns the translation of some site text, or the original until one arrives.
    ///
    /// Safe to call from a view's body: a miss is queued without notifying observers.
    func text(for original: String) -> String {
        guard isSupported, !original.isEmpty else { return original }
        // Remember it even while translation is off, so switching it on catches up
        // with what's already on screen instead of waiting for those views to
        // happen to redraw.
        remember(original)
        guard isEnabled else { return original }
        if let translation = translations[original] { return translation }
        enqueue(original)
        return original
    }

    /// Records text a view asked about, keeping the most recent ``seenLimit``.
    private func remember(_ original: String) {
        guard !recentlySeen.contains(original) else { return }
        recentlySeen.insert(original)
        seenOrder.append(original)
        if seenOrder.count > seenLimit {
            recentlySeen.remove(seenOrder.removeFirst())
        }
    }

    /// Queues everything on screen. Called when translation is switched on.
    private func enqueueEverythingSeen() {
        for original in seenOrder where translations[original] == nil {
            enqueue(original)
        }
    }

    /// Returns translations for a list of site text, such as a video's keywords.
    func text(for originals: [String]) -> [String] {
        originals.map { text(for: $0) }
    }

    private func enqueue(_ original: String) {
        guard !skipped.contains(original) else { return }
        guard let language = Self.language(of: original) else {
            skipped.insert(original)
            return
        }
        // Text already in the device's language needs nothing.
        guard language != targetLanguage.languageCode?.identifier else {
            skipped.insert(original)
            return
        }
        pending[language, default: []].insert(original)
        scheduleFlush()
    }

    /// Waits briefly so a screenful of cards becomes one batch instead of thirty.
    private func scheduleFlush() {
        guard isEnabled, isSupported, flushTask == nil, !pending.isEmpty else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.flushTask = nil
            await self?.beginNextBatch()
        }
    }

    // MARK: - Translating

    #if os(iOS) || os(macOS)
    /// Translates the next language group, or asks to download one.
    ///
    /// Languages the device already has go first, so the app translates everything
    /// it can before it considers asking for a download.
    private func beginNextBatch() async {
        guard isEnabled, !isTranslating, !pending.isEmpty else { return }

        // Most queued text first — that's the language a person is actually reading.
        let byVolume = pending.sorted { $0.value.count > $1.value.count }.map(\.key)

        var missing = [String]()
        for language in byVolume {
            if await isAvailable(from: language) {
                await translateBatch(from: language)
                return
            }
            // isAvailable prunes pairs the system can't do at all.
            if pending[language] != nil {
                languagesNeedingDownload.insert(language)
                missing.append(language)
            }
        }

        // Nothing translatable is queued. Offer to fetch the biggest missing one.
        guard downloadsAutomatically,
              !didRequestDownloadThisSession,
              let language = missing.first(where: { !askedLanguages.contains($0) }) else {
            return
        }
        didRequestDownloadThisSession = true
        requestDownload(of: language)
    }

    /// Translates everything queued for one language.
    ///
    /// An installed language pair needs no SwiftUI hosting — the session is built
    /// directly. Only the download request still needs a hosted session, because a
    /// directly built one reports `canRequestDownloads == false`.
    private func translateBatch(from language: String) async {
        let batch = Array(pending.removeValue(forKey: language) ?? [])
        guard !batch.isEmpty else { return }

        isTranslating = true
        defer {
            isTranslating = false
            if !pending.isEmpty { scheduleFlush() }
        }

        switch await Self.translate(batch, from: language, to: targetLanguage) {
        case .success(let results):
            // One write, so a page of cards redraws once rather than once per title.
            translations.merge(results) { _, new in new }
            cache.save(translations)
            lastError = nil
        case .failure(let reason):
            abandon(batch, reason: reason)
        }
    }

    /// The outcome of one batch, reduced to values that cross isolation safely.
    private enum BatchResult {
        case success([String: String])
        case failure(String)
    }

    /// Performs the translation away from the main actor.
    ///
    /// `TranslationSession` and its `Request` aren't `Sendable`, so both are created
    /// and consumed inside this one nonisolated function. Only strings come back.
    nonisolated private static func translate(
        _ texts: [String],
        from language: String,
        to target: Locale.Language
    ) async -> BatchResult {
        let session = TranslationSession(
            installedSource: Locale.Language(identifier: language),
            target: target
        )
        do {
            let requests = texts.map { TranslationSession.Request(sourceText: $0) }
            let responses = try await session.translations(from: requests)
            return .success(Dictionary(responses.map { ($0.sourceText, $0.targetText) },
                                       uniquingKeysWith: { _, new in new }))
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Downloading a language

    /// Asks the system to download the language the queued text needs.
    ///
    /// The profile screen calls this so a person can retry — or ask again for a
    /// language they declined earlier, which the automatic path won't do.
    func downloadMissingLanguages() {
        guard let language = languagesNeedingDownload.sorted().first else { return }
        requestDownload(of: language)
    }

    /// Points the hosted translation task at a language pair so it can offer the
    /// system's download UI. This is the one thing a directly built session can't do.
    private func requestDownload(of language: String) {
        rememberAsking(about: language)
        shouldPrepare = true

        let source = Locale.Language(identifier: language)
        if downloadConfiguration?.source == source {
            // The same pair as last time produces an equal value, which wouldn't
            // restart the task on its own.
            downloadConfiguration?.invalidate()
        } else {
            downloadConfiguration = TranslationSession.Configuration(source: source, target: targetLanguage)
        }
    }

    private func rememberAsking(about language: String) {
        askedLanguages.insert(language)
        UserDefaults.standard.set(Array(askedLanguages), forKey: Self.askedLanguagesKey)
    }

    /// Whether the next hosted session should offer to download its languages.
    @ObservationIgnored private var shouldPrepare = false

    /// Downloads the session's languages, then clears the flag.
    ///
    /// `ContentView` calls this from the one `translationTask` the app still hosts.
    nonisolated func completeDownload(using session: TranslationSession) async {
        guard await claimPreparation() else { return }
        guard session.canRequestDownloads else {
            await report("This device can’t request translation downloads.")
            return
        }
        do {
            try await session.prepareTranslation()
            await languageBecameAvailable(session.sourceLanguage?.languageCode?.identifier)
        } catch {
            await report("Unable to download a translation language: \(error.localizedDescription)")
        }
    }

    // MARK: - Main-actor state, reached from the nonisolated session work

    /// Stops retrying text the framework couldn't handle.
    private func abandon(_ batch: [String], reason: String) {
        logger.error("Unable to translate \(batch.count) strings: \(reason)")
        skipped.formUnion(batch)
        lastError = reason
    }

    private func claimPreparation() -> Bool {
        defer { shouldPrepare = false }
        return shouldPrepare
    }

    private func languageBecameAvailable(_ language: String?) {
        guard let language else { return }
        languagesNeedingDownload.remove(language)
        availability[key(from: language)] = true
        // The text that was waiting on it can go now.
        scheduleFlush()
    }

    private func report(_ message: String) {
        logger.error("\(message)")
        lastError = message
    }

    /// Returns whether the device can translate from a language right now.
    private func isAvailable(from language: String) async -> Bool {
        if let known = availability[key(from: language)] { return known }
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: language),
            to: targetLanguage
        )
        let installed = status == .installed
        availability[key(from: language)] = installed
        if status == .unsupported {
            // Nothing will ever translate this pair, so stop asking.
            pending.removeValue(forKey: language).map { skipped.formUnion($0) }
        }
        return installed
    }
    #else
    private func beginNextBatch() async {}
    func downloadMissingLanguages() {}
    #endif

    private func key(from language: String) -> String {
        "\(language)->\(targetLanguage.minimalIdentifier)"
    }

    /// Forgets every translation the app has cached.
    func clearCache() {
        translations = [:]
        skipped = []
        cache.removeAll()
    }

    // MARK: - Language detection

    /// The languages site text is realistically written in.
    ///
    /// Without a prior, the recognizer confuses scripts it sees rarely — a Russian
    /// title comes back as Kazakh with full confidence, and then nothing translates
    /// because that pair isn't installed. Weighting the languages tube sites
    /// actually publish in fixes that without hard-coding a single answer.
    nonisolated private static let languagePrior: [NLLanguage: Double] = [
        .english: 3, .russian: 3, .spanish: 2, .portuguese: 2, .german: 2,
        .french: 2, .italian: 2, .japanese: 2, .simplifiedChinese: 1.5,
        .traditionalChinese: 1, .korean: 1.5, .hindi: 1, .arabic: 1, .turkish: 1,
        .polish: 1, .dutch: 1, .czech: 1, .romanian: 1, .thai: 1, .vietnamese: 1,
        .indonesian: 1, .ukrainian: 1
    ]

    /// Returns the language some text appears to be written in.
    ///
    /// Short strings — a one-word keyword — often can't be identified with any
    /// confidence. Those return `nil` and stay untranslated rather than being
    /// mangled by a wrong guess.
    nonisolated static func language(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4, trimmed.rangeOfCharacter(from: .letters) != nil else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageHints = languagePrior
        recognizer.processString(trimmed)
        guard let hypothesis = recognizer.languageHypotheses(withMaximum: 1).max(by: { $0.value < $1.value }),
              hypothesis.value >= 0.5 else {
            return nil
        }
        return hypothesis.key.rawValue
    }
}

/// A small on-disk cache of translations, so they survive a relaunch.
private struct TranslationCache {
    let language: String

    private var url: URL {
        URL.applicationSupportDirectory.appending(path: "translations-\(language).json")
    }

    /// The most entries to keep. Listings repeat heavily, so this goes a long way.
    private let limit = 4000

    func load() -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return stored
    }

    func save(_ translations: [String: String]) {
        let trimmed = translations.count > limit
            ? Dictionary(uniqueKeysWithValues: translations.prefix(limit).map { ($0.key, $0.value) })
            : translations
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(trimmed) else { return }
            try? FileManager.default.createDirectory(
                at: URL.applicationSupportDirectory, withIntermediateDirectories: true
            )
            try? data.write(to: url, options: .atomic)
        }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: url)
    }
}
