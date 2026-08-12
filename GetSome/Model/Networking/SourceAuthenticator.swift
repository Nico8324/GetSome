/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Signs in to a site and holds the resulting session.
*/

import Foundation

/// What a source needs to describe in order to support signing in.
///
/// A site without accounts conforms to nothing and gains no sign-in interface.
protocol AuthenticatingSource: ContentSource {
    /// The page holding the sign-in form, which also carries the token it needs.
    var signInURL: URL { get }

    /// Builds the form body for a sign-in, given the token read from that page.
    func signInBody(username: String, password: String, token: String) -> Data

    /// Reads the one-time token a site's sign-in form requires.
    func signInToken(in html: String) -> String?

    /// Whether a page fetched after signing in shows a signed-in person.
    func isSignedIn(in html: String) -> Bool

    /// The site's own explanation for a refused sign-in, when it gives one.
    ///
    /// Returning `nil` means "not signed in, and the page said nothing about why",
    /// which the authenticator reports differently from a stated refusal — one is
    /// a wrong password, the other is a page this app can no longer read.
    func signInFailureReason(in html: String) -> String?
}

extension AuthenticatingSource {
    /// Looks for an error the site rendered next to its sign-in form.
    ///
    /// Deliberately generic: the exact markup can't be known without a failed
    /// sign-in to look at, and this is the one path that can't be rehearsed
    /// against the live site without an account.
    func signInFailureReason(in html: String) -> String? {
        let patterns = [
            #"<[^>]*class="[^"]*(?:error|alert|invalid)[^"]*"[^>]*>\s*([^<]{4,200}?)\s*<"#,
            #"<[^>]*(?:id|class)="[^"]*form-error[^"]*"[^>]*>\s*([^<]{4,200}?)\s*<"#
        ]
        for pattern in patterns {
            guard let found = HTMLScanner.firstMatch(of: pattern, in: html) else { continue }
            let message = HTMLScanner.decode(found).trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty { return message }
        }
        return nil
    }
}

/// Signs in to a site and holds the resulting session.
///
/// **This deliberately does not use ``ContentClient``.** That client records every
/// request it makes in ``RequestLog`` — URL, byte counts, and the body of the last
/// unparsed response — and Profile › Diagnostics can export the whole thing to a
/// file made for sending to someone else. A sign-in request carries a password in
/// its body, so routing it through that client would put credentials in a document
/// designed to be shared.
///
/// Keeping sign-in on its own session makes that structural. There is no flag to
/// remember to set and no redaction step to get wrong: the code that logs requests
/// and the code that sends passwords share nothing.
actor SourceAuthenticator {
    static let shared = SourceAuthenticator()

    /// Cookies are held per process, not written to disk, and dropped on sign-out.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        return URLSession(configuration: configuration)
    }()

    /// The sites signed in during this launch.
    private(set) var signedInSources = Set<String>()

    /// Signs in to a site and keeps the session for later requests.
    ///
    /// The credential is only stored once the site accepts it, so a typo doesn't
    /// leave a wrong password in the keychain for the next launch to retry.
    func signIn(to source: any AuthenticatingSource, username: String, password: String) async throws {
        let token = try await currentToken(for: source)

        var request = source.request(for: source.signInURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(source.signInURL.absoluteString, forHTTPHeaderField: "Referer")
        request.httpBody = source.signInBody(username: username, password: password, token: token)

        let (data, _) = try await session.data(for: request)
        let html = String(decoding: data, as: UTF8.self)

        // Plausibility first, because success is inferred from the *absence* of the
        // sign-in form — so a stub, a challenge page, or an empty body would all
        // read as signed in and get a password written to the keychain. Whatever a
        // site answers when it refuses, it answers with a page.
        guard html.count >= 2_000 else { throw CredentialError.unrecognizedResponse }

        guard source.isSignedIn(in: html) else {
            // Whether the site *said* why separates "wrong password" from "this app
            // can no longer read the page". Without that split, both look identical
            // to whoever has to fix it.
            throw source.signInFailureReason(in: html)
                .map(CredentialError.rejectedWithReason) ?? CredentialError.rejected
        }

        try CredentialStore.save(Credential(username: username, password: password), for: source.id)
        signedInSources.insert(source.id)
    }

    /// Signs in again using a stored credential, if there is one.
    ///
    /// Sessions don't survive a relaunch, so this runs before the first request to
    /// a page that needs one rather than at launch — a person who never opens their
    /// playlists never sends their password anywhere.
    @discardableResult
    func restoreSession(for source: any AuthenticatingSource) async -> Bool {
        if signedInSources.contains(source.id) { return true }
        guard let credential = CredentialStore.credential(for: source.id) else { return false }
        do {
            try await signIn(to: source, username: credential.username, password: credential.password)
            return true
        } catch {
            // Deliberately quiet about which part failed: a wrong password and an
            // unreachable site look the same here, and neither is worth a log line
            // that names the account.
            logger.error("Couldn’t restore the \(source.displayName, privacy: .public) session.")
            return false
        }
    }

    /// Fetches a page that needs the signed-in session.
    func page(at url: URL, from source: any AuthenticatingSource) async throws -> SourceResponse {
        guard await restoreSession(for: source) else { throw CredentialError.rejected }
        let (data, response) = try await session.data(for: source.request(for: url))
        return SourceResponse(url: response.url ?? url, data: data)
    }

    /// Forgets a site's session and its stored credential.
    func signOut(of source: any ContentSource) {
        signedInSources.remove(source.id)
        CredentialStore.remove(for: source.id)
        if let cookies = session.configuration.httpCookieStorage?.cookies(for: source.homeURL) {
            for cookie in cookies { session.configuration.httpCookieStorage?.deleteCookie(cookie) }
        }
    }

    /// Reads the sign-in form's one-time token, which also seeds the session cookie.
    private func currentToken(for source: any AuthenticatingSource) async throws -> String {
        let (data, _) = try await session.data(for: source.request(for: source.signInURL))
        guard let token = source.signInToken(in: String(decoding: data, as: UTF8.self)) else {
            throw CredentialError.missingToken
        }
        return token
    }
}
