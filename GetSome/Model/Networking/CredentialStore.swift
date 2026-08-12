/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Stores site sign-in credentials in the keychain.
*/

import Foundation
import Security

/// A person's sign-in details for one site.
struct Credential: Sendable, Equatable {
    let username: String
    let password: String
}

/// Stores site sign-in credentials in the keychain.
///
/// The keychain rather than `UserDefaults` because these are real passwords for
/// other people's sites: defaults are a plain plist inside the container, readable
/// by anything that can read the container and swept up by a device backup.
///
/// Credentials never appear anywhere else. In particular they must not reach
/// ``RequestLog`` — see ``SourceAuthenticator`` for why that's structural rather
/// than a matter of remembering.
enum CredentialStore {
    /// Saves a credential, replacing any already stored for the site.
    static func save(_ credential: Credential, for sourceID: String) throws {
        remove(for: sourceID)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sourceID,
            kSecAttrLabel as String: credential.username,
            kSecValueData as String: Data(credential.password.utf8),
            // Never leaves this device: a credential restored onto another phone
            // from a backup is a surprise nobody asked for.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialError.keychain(status) }
    }

    /// Returns the credential stored for a site, if there is one.
    static func credential(for sourceID: String) -> Credential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sourceID,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let found = item as? [String: Any],
              let data = found[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8),
              let username = found[kSecAttrLabel as String] as? String
        else { return nil }
        return Credential(username: username, password: password)
    }

    /// Forgets the credential stored for a site.
    static func remove(for sourceID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sourceID
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Whether a site has a credential stored, without reading the password back.
    static func hasCredential(for sourceID: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sourceID
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private static let service = "com.getsome.GetSome.siteCredentials"
}

/// Why storing or using a credential failed.
enum CredentialError: LocalizedError {
    case keychain(OSStatus)
    case missingToken
    case rejected
    case rejectedWithReason(String)
    case unrecognizedResponse

    var errorDescription: String? {
        switch self {
        case .keychain:
            String(localized: "This device couldn’t store the sign-in details.",
                   comment: "An error shown when the keychain refuses to save a credential")
        case .missingToken:
            String(localized: "The site’s sign-in page didn’t look the way this app expects.",
                   comment: "An error shown when a site's sign-in form can't be read")
        case .rejected:
            String(localized: "The site didn’t accept that email and password.",
                   comment: "An error shown when a site rejects a sign-in")
        case .rejectedWithReason(let reason):
            // The site's own words, which say more than a generic refusal can —
            // an unverified address or a locked account read very differently.
            reason
        case .unrecognizedResponse:
            // Deliberately distinct from a rejection: this means the app couldn't
            // tell whether the sign-in worked, which is a different thing to fix.
            String(localized: "The site answered, but this app couldn’t tell whether the sign-in worked. Its sign-in page has probably changed.",
                   comment: "An error shown when a sign-in response can't be interpreted")
        }
    }
}
