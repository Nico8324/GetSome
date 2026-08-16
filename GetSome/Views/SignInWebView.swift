/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Presents a site's own sign-in page so a person can sign in themselves.
*/

#if !os(tvOS)
import SwiftUI
@preconcurrency import WebKit

/// Presents a site's own sign-in page so a person can sign in themselves.
///
/// The app used to post the form itself, which meant holding someone's password for
/// another site and rebuilding a form that can change without notice. Showing the
/// real page is better on both counts: **the app never sees the password**, and
/// whatever the site asks for — a CAPTCHA, a device confirmation, two factors — is
/// asked of the person who can actually answer it.
///
/// What the app keeps is the session that results, and nothing else.
struct SignInWebView: View {
    let source: any AuthenticatingSource

    /// Called with the cookies the site set, once the person is signed in.
    let onSignedIn: @Sendable @MainActor ([HTTPCookie]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSignedIn = false

    var body: some View {
        NavigationStack {
            WebView(source: source, isSignedIn: $isSignedIn) { cookies in
                onSignedIn(cookies)
                dismiss()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(source.displayName)
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// The web view that loads the sign-in page and watches for a session.
@MainActor
private struct WebView {
    let source: any AuthenticatingSource
    @Binding var isSignedIn: Bool
    let finish: @Sendable @MainActor ([HTTPCookie]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(source: source, finish: finish)
    }

    func makeView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // A non-persistent store, so signing out of the app really does leave
        // nothing behind — and so this never inherits some earlier session.
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: source.signInURL))
        return view
    }

    /// Watches each page for the moment the sign-in form stops being there.
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let source: any AuthenticatingSource
        private let finish: @Sendable @MainActor ([HTTPCookie]) -> Void
        private var didFinish = false

        init(source: any AuthenticatingSource, finish: @escaping @Sendable @MainActor ([HTTPCookie]) -> Void) {
            self.source = source
            self.finish = finish
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            MainActor.assumeIsolated { self.pageDidLoad(webView) }
        }

        private func pageDidLoad(_ webView: WKWebView) {
            guard !didFinish else { return }
            // The same test the app uses everywhere else: the sign-in form is served
            // to anyone who isn't signed in, so its absence is the signal.
            webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
                guard let self, !self.didFinish,
                      let html = result as? String,
                      self.source.isSignedIn(in: html) else { return }
                self.didFinish = true
                let host = self.source.homeURL.host() ?? ""
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    // Only this site's cookies. A web view collects whatever the page
                    // loads, and an ad network's cookies are neither ours to keep nor
                    // any use for reading an account.
                    let mine = cookies.filter {
                        host.hasSuffix($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                    }
                    MainActor.assumeIsolated { self.finish(mine) }
                }
            }
        }
    }
}

#if os(macOS)
extension WebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeView(context: context) }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#else
extension WebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeView(context: context) }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif
#endif
