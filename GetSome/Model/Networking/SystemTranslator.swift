/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Translates site text on the device, using the system's translation models.
*/

// An allowlist rather than a list of exclusions, because importing the framework
// proves nothing: tvOS and visionOS both import Translation happily and then have
// no TranslationSession to hand out. Where this is false the app falls back to the
// network service, which works everywhere.
//
// Both call sites — the default service in TranslationStore and the session bridge
// in ContentView — must spell this condition the same way. When they drifted apart,
// only the visionOS build noticed, and only at the point of use.
#if canImport(Translation) && (os(iOS) || os(macOS))
import SwiftUI
import Translation

/// Translates site text on the device, using the system's translation models.
///
/// This is the service the app prefers: nothing leaves the device, nothing rate
/// limits, and a downloaded language works offline. The one architectural wrinkle
/// is that the framework only hands out a ``TranslationSession`` through the
/// `translationTask` view modifier — there is no way to just ask for one. So this
/// object is a bridge: ``translate(_:from:to:)`` parks the batch and publishes a
/// session configuration, a hidden view in ``ContentView`` observes that and
/// receives the session, and ``perform(with:)`` finishes the job.
///
/// It only ever uses languages **already downloaded** to the device. Tube sites
/// publish in a dozen languages, and downloading a model for each would quietly
/// cost gigabytes of storage — so a pair that isn't installed is refused here and
/// handled by the fallback service instead, and languages someone downloads in
/// the system's Translate app start being used automatically.
@MainActor
@Observable
final class SystemTranslator: TranslationService {
    static let shared = SystemTranslator()

    /// What the bridge view should build a session for. Observed by ``ContentView``.
    private(set) var configuration: TranslationSession.Configuration?

    private struct Work {
        let texts: [String]
        let continuation: CheckedContinuation<[String], Error>
    }

    @ObservationIgnored private var work: Work?
    @ObservationIgnored private var timeout: Task<Void, Never>?

    func translate(_ texts: [String], from source: String?, to target: String) async throws -> [String] {
        guard !texts.isEmpty else { throw TranslationServiceError.emptyBatch }
        // The store sends one batch at a time; a second caller is a bug, but hanging
        // its continuation forever would be a worse one.
        guard work == nil else { throw TranslationServiceError.translatorBusy }

        let sourceLanguage = source.map { Locale.Language(identifier: $0) }
        let targetLanguage = Locale.Language(identifier: target)

        // Installed, not merely supported: a supported-but-absent pair would make
        // the session offer a model download, and this app doesn't spend someone's
        // storage on a language pack per site language. Refusing here sends the
        // batch to the fallback instead.
        if let sourceLanguage {
            let status = await LanguageAvailability().status(from: sourceLanguage, to: targetLanguage)
            guard status == .installed else { throw TranslationServiceError.unsupportedLanguage }
        }

        return try await withCheckedThrowingContinuation { continuation in
            work = Work(texts: texts, continuation: continuation)

            // If the bridge never answers — the view is gone, or the framework has
            // no session to give — fail the batch rather than wedging the queue.
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.fail(with: TranslationServiceError.translatorUnavailable)
            }

            // Reusing an equal configuration wouldn't re-run the bridge's task, so a
            // repeat pair is invalidated instead of replaced.
            if var current = configuration,
               current.source == sourceLanguage, current.target == targetLanguage {
                current.invalidate()
                configuration = current
            } else {
                configuration = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
            }
        }
    }

    /// A parked batch, handed to the bridge view to finish.
    ///
    /// The session itself can't come here: it isn't `Sendable`, so the work has to
    /// travel to the closure that owns the session rather than the other way round.
    struct PendingBatch: Sendable {
        let texts: [String]
        let continuation: CheckedContinuation<[String], Error>
    }

    /// Hands the parked batch to the bridge view, exactly once.
    func takeWork() -> PendingBatch? {
        guard let work else { return nil }
        self.work = nil
        timeout?.cancel()
        timeout = nil
        return PendingBatch(texts: work.texts, continuation: work.continuation)
    }

    /// Carries a session across an isolation boundary it can't cross on its own.
    ///
    /// `TranslationSession` isn't `Sendable`, and the compiler is right that it
    /// usually shouldn't travel. Here it makes exactly one hop — from the bridge
    /// view's closure into ``finish(_:batch:)`` — and is used by one task, serially,
    /// then dropped. The box states that invariant rather than scattering the
    /// batch logic through a view file to avoid it.
    struct SessionBox: @unchecked Sendable {
        let session: TranslationSession
    }

    /// Runs the parked batch through the session and resumes the waiting caller.
    nonisolated static func finish(_ box: SessionBox, batch: PendingBatch) async {
        do {
            let responses = try await box.session.translations(
                from: batch.texts.map { TranslationSession.Request(sourceText: $0) }
            )
            guard responses.count == batch.texts.count else {
                throw TranslationServiceError.misalignedResponse(
                    sent: batch.texts.count, received: responses.count
                )
            }
            batch.continuation.resume(returning: responses.map(\.targetText))
        } catch {
            batch.continuation.resume(throwing: error)
        }
    }

    private func fail(with error: TranslationServiceError) {
        guard let work else { return }
        self.work = nil
        timeout?.cancel()
        timeout = nil
        work.continuation.resume(throwing: error)
    }
}
#endif

/// Tries one service and falls back to another when it can't answer.
///
/// The pairing the app uses is device first, network second: the device answers
/// most batches for free and in private, and the network service only ever sees
/// the languages the device genuinely can't translate.
struct FallbackTranslator: TranslationService {
    let primary: any TranslationService
    let fallback: any TranslationService

    func translate(_ texts: [String], from source: String?, to target: String) async throws -> [String] {
        do {
            return try await primary.translate(texts, from: source, to: target)
        } catch {
            return try await fallback.translate(texts, from: source, to: target)
        }
    }
}
