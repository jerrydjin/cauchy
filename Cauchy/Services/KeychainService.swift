import Foundation
import Security

/// One Keychain item per BYOK provider. The item's service/account pair comes
/// from `CloudAPIProvider`, which keeps Gemini's pre-BYOK identity so keys
/// saved by earlier versions are still found.
enum KeychainService {
    /// Whether a key is stored, without decrypting it. `loadKey` passes
    /// `kSecReturnData`, which reads the secret itself and can raise a keychain
    /// access prompt — after any re-signing of the app, that fires on every
    /// call. UI gating runs from SwiftUI bodies (menus re-evaluate on each
    /// render), so it must use this instead; load the key only at the point of
    /// actually calling the API.
    static func hasKey(for provider: CloudAPIProvider) -> Bool {
        var query = baseQuery(for: provider)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// True when any provider has a key saved — the cheap gate for "is BYOK set
    /// up at all", safe to call from a view body.
    static var hasAnyKey: Bool {
        CloudAPIProvider.allCases.contains(where: hasKey(for:))
    }

    static func loadKey(for provider: CloudAPIProvider) -> String? {
        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func saveKey(_ key: String, for provider: CloudAPIProvider) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteKey(for: provider)
            return
        }

        let data = Data(trimmed.utf8)
        let query = baseQuery(for: provider)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.saveFailed(addStatus)
            }
            return
        }
        throw KeychainError.saveFailed(updateStatus)
    }

    static func deleteKey(for provider: CloudAPIProvider) throws {
        let status = SecItemDelete(baseQuery(for: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    private static func baseQuery(for provider: CloudAPIProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: provider.keychainService,
            kSecAttrAccount as String: provider.keychainAccount,
        ]
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Could not save API key to Keychain (status \(status))."
        case .deleteFailed(let status):
            return "Could not remove API key from Keychain (status \(status))."
        }
    }
}
