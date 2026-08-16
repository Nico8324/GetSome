/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Translates site text with a free online service.
*/

import Foundation

/// Something that can translate a batch of site text.
///
/// One call carries a whole screen of titles, because a service that charges by the
/// request — in quota, in rate limiting, or just in latency — makes thirty single
/// translations far more expensive than one batch of thirty.
protocol TranslationService: Sendable {
    /// Translates `texts` and returns the results **positionally**.
    ///
    /// The result always has the same count and order as the input. A service that
    /// can't guarantee that must throw rather than return a short array, because the
    /// caller pairs results back to originals by index — a misaligned batch would
    /// silently show one video's title on another.
    func translate(_ texts: [String], from source: String?, to target: String) async throws -> [String]
}

/// Why a translation attempt failed.
enum TranslationServiceError: LocalizedError {
    case emptyBatch
    case badResponse(Int)
    case unreadableResponse
    case misalignedResponse(sent: Int, received: Int)
    case rateLimited
    case unsupportedLanguage
    case translatorBusy
    case translatorUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyBatch:
            String(localized: "There was nothing to translate.")
        case .badResponse(let status):
            String(localized: "The translation service answered \(status).")
        case .unreadableResponse:
            String(localized: "The translation service sent something unreadable.")
        case .misalignedResponse(let sent, let received):
            String(localized: "The translation service returned \(received) results for \(sent) items.")
        case .rateLimited:
            String(localized: "The translation service is rate limiting this device. Try again later.")
        case .unsupportedLanguage:
            String(localized: "This device can’t translate that language.")
        case .translatorBusy:
            String(localized: "A translation is already running.")
        case .translatorUnavailable:
            String(localized: "Translation on this device didn’t answer.")
        }
    }
}

/// Translates with Google's public `translate_a` endpoint.
///
/// This is the endpoint Google's own web widget calls. It needs no key and no
/// account, which is the whole reason it's here — every alternative that was free
/// without a key either wants one now or has gone offline.
///
/// It is not a documented API, so treat it as a site being scraped rather than a
/// service being consumed: it can change shape or start refusing requests without
/// notice. ``TranslationService`` exists so replacing it is one new type.
struct GoogleTranslator: TranslationService {
    /// The most strings to put in one request.
    ///
    /// The endpoint takes far more, but a failed batch costs everything in it — and
    /// a screen of cards is about this many, so a bigger batch mostly adds risk.
    static let batchLimit = 24

    /// The most characters to put in one request, whichever limit is reached first.
    static let characterLimit = 1800

    private let endpoint = URL(string: "https://translate.googleapis.com/translate_a/single")!

    func translate(_ texts: [String], from source: String?, to target: String) async throws -> [String] {
        guard !texts.isEmpty else { throw TranslationServiceError.emptyBatch }

        // Newlines are the record separator, so text containing one would come back
        // as two results and shift every later title onto the wrong video.
        let flattened = texts.map { $0.replacingOccurrences(of: "\n", with: " ")
                                     .replacingOccurrences(of: "\r", with: " ") }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8",
                         forHTTPHeaderField: "Content-Type")
        // Sent as a body rather than a query so a long batch can't exceed a URL limit.
        request.httpBody = Self.form(flattened, from: source, to: target)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw status == 429 ? TranslationServiceError.rateLimited
                                : TranslationServiceError.badResponse(status)
        }

        let lines = try Self.lines(in: data)
        guard lines.count == flattened.count else {
            throw TranslationServiceError.misalignedResponse(sent: flattened.count, received: lines.count)
        }
        // An empty result means that line came back with nothing usable; keep the
        // original rather than blanking a title.
        return zip(texts, lines).map { $0.1.isEmpty ? $0.0 : $0.1 }
    }

    /// Builds the form body. `sl=auto` is a last resort — see ``TranslationStore``.
    private static func form(_ texts: [String], from source: String?, to target: String) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?")
        let joined = texts.joined(separator: "\n")
        let encoded = joined.addingPercentEncoding(withAllowedCharacters: allowed) ?? joined
        let query = "client=gtx&sl=\(source ?? "auto")&tl=\(target)&dt=t&q=\(encoded)"
        return Data(query.utf8)
    }

    /// Pulls the translated lines out of the endpoint's nested-array response.
    ///
    /// The reply is a bare JSON array, not an object: the first element holds the
    /// translated chunks, each chunk an array whose first element is the text. The
    /// service splits on its own terms, so the chunks are reassembled and then split
    /// on newlines — the separators that went in.
    private static func lines(in data: Data) throws -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let chunks = root.first as? [Any] else {
            throw TranslationServiceError.unreadableResponse
        }
        let combined = chunks.compactMap { ($0 as? [Any])?.first as? String }.joined()
        return combined.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
