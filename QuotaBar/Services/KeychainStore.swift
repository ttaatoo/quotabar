import Foundation
import Security

enum KeychainAccount: Hashable {
    case cursorCookie
    case chatgptCookie
    case chatgptJSON
    case glmAPIKey
    case chatgptAccountCookie(UUID)
    case chatgptAccountJSON(UUID)

    var rawValue: String {
        switch self {
        case .cursorCookie:
            return "cursor.cookie"
        case .chatgptCookie:
            return "chatgpt.cookie"
        case .chatgptJSON:
            return "chatgpt.usage-json"
        case .glmAPIKey:
            return "glm.api-key"
        case .chatgptAccountCookie(let id):
            return "chatgpt.cookie.\(id.uuidString)"
        case .chatgptAccountJSON(let id):
            return "chatgpt.json.\(id.uuidString)"
        }
    }
}

enum KeychainStore {
    private static let service = "app.quotabar.QuotaBar"

    static func set(_ value: String?, account: KeychainAccount) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            delete(account)
            return
        }

        let data = Data(trimmed.utf8)
        var query = baseQuery(account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess {
            return
        }
        if updated == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(query as CFDictionary, nil)
            return
        }
        delete(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ account: KeychainAccount) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    static func delete(_ account: KeychainAccount) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private static func baseQuery(_ account: KeychainAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]
    }
}
