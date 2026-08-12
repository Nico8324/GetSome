/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Translates the text that sources publish into the language of the device.
*/

import Foundation
import NaturalLanguage
import SwiftUI

/// Translates the text that sources publish into the language of the device.
///
/// Sites publish titles and keywords in whatever language they were uploaded in —
/// often several within one listing. This object collects that text, groups it by
/// the language it appears to be written in, and sends each group to a
/// ``TranslationService``. Results are cached, so a title is translated once and
/// then survives relaunches.
///
/// Views ask for text through ``text(for:)``, which answers immediately with the
/// original and swaps in a translation when one arrives.
///
/// **This sends text off the device.** Titles and keywords go to a third-party
/// service, which is why it stays off until switched on — see ``isEnabled``.
/// Language detection is the one part that stays local, which also means text
/// already in the device's language is never sent anywhere.
@MainActor
@Observable
final class TranslationStore {
    /// The user defaults key that holds whether translation is on.
    static let isEnabledKey = "translateSiteText"

    /// Whether the app translates the text sources publish.
    ///
    /// Off until asked for. Translating sends what you're browsing to a third party,
    /// so the app doesn't decide that on someone's behalf — and while it's off,
    /// nothing is detected, queued, or sent.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.isEnabledKey)
            guard isEnabled else { return }
            lastError = nil
            enqueueEverythingSeen()
            scheduleFlush()
        }
    }

    /// The language to translate into.
    let targetLanguage: Locale.Language

    /// Translations of site text, keyed by the original.
    ///
    /// Written a batch at a time so a page of cards redraws once per batch rather
    /// than once per title.
    private(set) var translations = [String: String]()

    /// A Boolean value that indicates whether a batch is in flight.
    private(set) var isTranslating = false

    /// Why the last attempt failed, if it did.
    ///
    /// Worth surfacing rather than swallowing: the service can start refusing
    /// requests, and without this the app would just quietly stop translating.
    private(set) var lastError: String?

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

    /// When the service last asked to be left alone, if it did.
    ///
    /// A rate-limited batch goes back in the queue rather than being abandoned — it
    /// is a temporary refusal, unlike text the service can't handle at all.
    @ObservationIgnored private var retryAfter: Date?

    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private let cache: TranslationCache
    @ObservationIgnored private let service: any TranslationService

    init(targetLanguage: Locale.Language = Locale.current.language,
         service: any TranslationService = GoogleTranslator()) {
        self.targetLanguage = targetLanguage
        self.service = service
        self.isEnabled = UserDefaults.standard.object(forKey: Self.isEnabledKey) as? Bool ?? false
        self.cache = TranslationCache(language: targetLanguage.minimalIdentifier)
        self.translations = cache.load()
    }

    /// The name of the target language, for the profile screen.
    var targetLanguageName: String {
        Locale.current.localizedString(forIdentifier: targetLanguage.minimalIdentifier)
            ?? targetLanguage.minimalIdentifier
    }

    /// The code the service is asked to translate into.
    private var targetCode: String {
        targetLanguage.languageCode?.identifier ?? "en"
    }

    // MARK: - Asking for text

    /// Returns the translation of some site text, or the original until one arrives.
    ///
    /// Safe to call from a view's body: a miss is queued without notifying observers.
    func text(for original: String) -> String {
        guard !original.isEmpty else { return original }
        // Remember it even while translation is off, so switching it on catches up
        // with what's already on screen instead of waiting for those views to
        // happen to redraw.
        remember(original)
        guard isEnabled else { return original }
        if let translation = translations[original] { return translation }
        enqueue(original)
        return original
    }

    /// Returns translations for a list of site text, such as a video's keywords.
    func text(for originals: [String]) -> [String] {
        originals.map { text(for: $0) }
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

    private func enqueue(_ original: String) {
        guard !skipped.contains(original) else { return }
        guard let language = Self.language(of: original) else {
            skipped.insert(original)
            return
        }
        // Text already in the device's language needs nothing — and this is what
        // keeps it from being sent anywhere.
        guard language != targetLanguage.languageCode?.identifier else {
            skipped.insert(original)
            return
        }
        pending[language, default: []].insert(original)
        scheduleFlush()
    }

    /// Waits briefly so a screenful of cards becomes one batch instead of thirty.
    private func scheduleFlush() {
        guard isEnabled, flushTask == nil, !pending.isEmpty else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.flushTask = nil
            await self?.translateNextBatch()
        }
    }

    // MARK: - Translating

    /// Translates one batch, then schedules the next if anything is still queued.
    ///
    /// Batches are per-language because the service detects a single language for
    /// everything it's given: mixing languages in one request leaves some of them
    /// untranslated. Telling it the language outright avoids that, and the detection
    /// happens on device anyway.
    private func translateNextBatch() async {
        guard isEnabled, !isTranslating, !pending.isEmpty else { return }

        // Still being rate limited — come back later rather than burning the batch.
        if let retryAfter, retryAfter > .now {
            scheduleRetry(at: retryAfter)
            return
        }

        // Most queued text first — that's the language a person is actually reading.
        guard let language = pending.max(by: { $0.value.count < $1.value.count })?.key else { return }
        let batch = takeBatch(for: language)
        guard !batch.isEmpty else { return }

        isTranslating = true
        defer {
            isTranslating = false
            if !pending.isEmpty { scheduleFlush() }
        }

        do {
            let results = try await service.translate(batch, from: language, to: targetCode)
            // One write, so a page of cards redraws once rather than once per title.
            translations.merge(zip(batch, results)) { _, new in new }
            cache.save(translations)
            lastError = nil
            retryAfter = nil
        } catch TranslationServiceError.rateLimited {
            // A temporary refusal: put the work back rather than losing it.
            pending[language, default: []].formUnion(batch)
            let resume = Date.now.addingTimeInterval(60)
            retryAfter = resume
            lastError = TranslationServiceError.rateLimited.localizedDescription
            scheduleRetry(at: resume)
        } catch {
            abandon(batch, reason: error.localizedDescription)
        }
    }

    /// Removes up to one request's worth of text from a language's queue.
    private func takeBatch(for language: String) -> [String] {
        guard var queue = pending[language] else { return [] }
        var batch = [String]()
        var characters = 0
        for text in queue.sorted() {
            let next = characters + text.count + 1
            if !batch.isEmpty && (batch.count >= GoogleTranslator.batchLimit
                                  || next > GoogleTranslator.characterLimit) { break }
            batch.append(text)
            characters = next
        }
        queue.subtract(batch)
        pending[language] = queue.isEmpty ? nil : queue
        return batch
    }

    private func scheduleRetry(at date: Date) {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, date.timeIntervalSinceNow)))
            self?.flushTask = nil
            await self?.translateNextBatch()
        }
    }

    /// Stops retrying text the service couldn't handle.
    private func abandon(_ batch: [String], reason: String) {
        logger.error("Unable to translate \(batch.count) strings: \(reason)")
        skipped.formUnion(batch)
        lastError = reason
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
    /// title comes back as Kazakh with full confidence, and then that group is sent
    /// off labelled as the wrong language. Weighting the languages tube sites
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
    /// mangled by a wrong guess, which also keeps them off the network.
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
