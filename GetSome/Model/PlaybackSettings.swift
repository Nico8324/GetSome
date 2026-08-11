/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The playback preferences a person sets on the profile screen.
*/

import Foundation

/// The tallest stream the app should choose when a source offers several.
enum StreamQuality: Int, CaseIterable, Identifiable, Sendable {
    /// Let the app pick, based on what the current device streams comfortably.
    case auto = 0
    case p360 = 360
    case p480 = 480
    case p720 = 720
    case p1080 = 1080

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .auto: String(localized: "Automatic", comment: "A video quality setting")
        default: "\(rawValue)p"
        }
    }

    var detail: String? {
        switch self {
        case .auto:
            String(localized: "Up to \(Self.platformDefault)p on this device.",
                   comment: "An explanation of the automatic video quality setting")
        default:
            nil
        }
    }

    /// The tallest stream to choose for this setting.
    var ceiling: Int {
        self == .auto ? Self.platformDefault : rawValue
    }

    /// The ceiling the app uses when a person hasn't chosen one.
    static var platformDefault: Int {
        #if os(tvOS) || os(macOS) || os(visionOS)
        1080
        #else
        720
        #endif
    }
}

/// The playback preferences a person sets on the profile screen.
///
/// These read straight from user defaults so any context can consult them —
/// including ``ContentSource/preferredStream(from:)``, which runs off the main
/// actor while resolving a stream.
enum PlaybackSettings {
    /// The user defaults key that ``StreamQuality`` is stored under.
    static let maximumQualityKey = "maximumStreamQuality"

    /// The tallest stream to choose. Defaults to ``StreamQuality/auto``.
    static var maximumQuality: StreamQuality {
        StreamQuality(rawValue: UserDefaults.standard.integer(forKey: maximumQualityKey)) ?? .auto
    }
}
