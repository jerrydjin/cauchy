import Foundation
import Security

enum KeychainService {
    private static let geminiKeyAccount = "gemini-api-key"
    private static let geminiKeyService = "com.cauchy.gemini-api-key"

    /// Whether a key is stored, without decrypting it. `loadGeminiAPIKey`
    /// passes `kSecReturnData`, which reads the secret itself and can raise a
    /// keychain access prompt — after any re-signing of the app, that fires on
    /// every call. UI gating runs from SwiftUI bodies (menus re-evaluate on
    /// each render), so it must use this instead; load the key only at the
    /// point of actually calling Gemini.
    static var hasGeminiAPIKey: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: geminiKeyService,
            kSecAttrAccount as String: geminiKeyAccount,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func loadGeminiAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: geminiKeyService,
            kSecAttrAccount as String: geminiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func saveGeminiAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteGeminiAPIKey()
            return
        }

        let data = Data(trimmed.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: geminiKeyService,
            kSecAttrAccount as String: geminiKeyAccount,
        ]

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

    static func deleteGeminiAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: geminiKeyService,
            kSecAttrAccount as String: geminiKeyAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
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
