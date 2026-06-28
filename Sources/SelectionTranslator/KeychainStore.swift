import Foundation
import Security

final class KeychainStore {
    private let service = "SelectionTranslator"
    private let account = "openai_api_key"

    func readAPIKey() -> String? {
        readAPIKey(account: account)
    }

    func readAPIKey(for provider: TranslationProvider) -> String? {
        if let apiKey = readAPIKey(account: accountName(for: provider)) {
            return apiKey
        }

        if provider == .anthropicNative, TranslationProvider.savedValue() == .anthropicNative {
            return readAPIKey()
        }

        return nil
    }

    private func readAPIKey(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func saveAPIKey(_ apiKey: String) throws {
        try saveAPIKey(apiKey, account: account)
    }

    func saveAPIKey(_ apiKey: String, for provider: TranslationProvider) throws {
        try saveAPIKey(apiKey, account: accountName(for: provider))
    }

    private func saveAPIKey(_ apiKey: String, account: String) throws {
        let data = Data(apiKey.utf8)
        var query = baseQuery(account: account)

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let attributes = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(updateStatus)
            }
        } else if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(addStatus)
            }
        } else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func accountName(for provider: TranslationProvider) -> String {
        switch provider {
        case .openAICompatible:
            return account
        case .anthropicNative:
            return "anthropic_api_key"
        case .deepLX:
            return "deeplx_api_key"
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum KeychainError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            return "Keychain 操作失败：\(status)"
        }
    }
}
