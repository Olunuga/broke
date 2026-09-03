//
//  TagSecret.swift
//  Broke
//
//  Per-install NFC tag secret. Only the hash is kept, so reading it back off the
//  device doesn't yield anything writable to a tag.
//

import Foundation
import CryptoKit
import Security

enum TagSecret {
    private static let service = "com.Brokeest.ios.tag"
    private static let account = "tagSecretHash"

    /// Whether a tag has ever been written by this install. Gates the create-tag
    /// button: available until a tag exists, hidden while blocking once one does.
    static var isRegistered: Bool {
        storedHash() != nil
    }

    /// Generates a new secret, stores its hash, and returns the secret to write to a
    /// tag. Any tag written earlier stops working.
    static func generate() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            NSLog("Broke: failed to generate tag secret")
            return nil
        }
        let secret = "BROKE-" + Data(bytes).base64EncodedString()
        guard store(hash(of: secret)) else { return nil }
        return secret
    }

    static func matches(_ payload: String) -> Bool {
        guard let stored = storedHash() else { return false }
        return hash(of: payload) == stored
    }

    private static func hash(of value: String) -> Data {
        Data(SHA256.hash(data: Data(value.utf8)))
    }

    // MARK: - Keychain

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func storedHash() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func store(_ hash: Data) -> Bool {
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData as String] = hash
        // The app reads this on a blocked screen, which the user reaches without
        // unlocking past first-unlock, so kSecAttrAccessibleAfterFirstUnlock rather
        // than WhenUnlocked.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("Broke: failed to store tag secret hash, status \(status)")
            return false
        }
        return true
    }
}
