/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Lets the full-window player rotate while the rest of the app stays portrait.
*/

#if os(iOS)
import UIKit

/// Lets the full-window player rotate while the rest of the app stays portrait.
///
/// The player is a SwiftUI view inside the app's own window rather than a
/// separately presented controller, so it can only rotate if the app itself
/// allows landscape. Allowing it everywhere would rotate the browsing screens
/// too, and the inherited card layouts are built for portrait on iPhone.
///
/// So the app declares landscape as *supported* in its Info.plist — without that
/// the system never offers it — and narrows the answer at runtime to the moment a
/// video is playing full window.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// The orientations the app allows right now.
    ///
    /// Setting this doesn't rotate anything by itself: UIKit caches the answer and
    /// only asks again when a view controller says its preference changed, which is
    /// what the observer below arranges.
    @MainActor static var supportedOrientations: UIInterfaceOrientationMask = .portrait {
        didSet {
            guard supportedOrientations != oldValue else { return }
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        // UIKit calls this on the main thread, but it isn't annotated as such.
        MainActor.assumeIsolated { Self.supportedOrientations }
    }
}
#endif
