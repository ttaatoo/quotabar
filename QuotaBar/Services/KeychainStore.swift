import Foundation
#if canImport(Security)
import Security
#endif

enum KeychainAccount: Hashable {
    case cursorCookie
    /// QuotaBar-owned replacement after a desktop token refresh. Not the Advanced cookie.
    case cursorRefreshedSession
    case chatgptCookie
    case chatgptJSON
    case glmAPIKey
    case grokOAuthToken
    case chatgptAccountCookie(UUID)
    case chatgptAccountJSON(UUID)
    case opencodeGoAPIKey(UUID)
    case grokAccountOAuthToken(UUID)

    var rawValue: String {
        switch self {
        case .cursorCookie:
            return "cursor.cookie"
        case .cursorRefreshedSession:
            return "cursor.refreshed-session"
        case .chatgptCookie:
            return "chatgpt.cookie"
        case .chatgptJSON:
            return "chatgpt.usage-json"
        case .glmAPIKey:
            return "glm.api-key"
        case .grokOAuthToken:
            return "grok.oauth-token"
        case .chatgptAccountCookie(let id):
            return "chatgpt.cookie.\(id.uuidString)"
        case .chatgptAccountJSON(let id):
            return "chatgpt.json.\(id.uuidString)"
        case .opencodeGoAPIKey(let id):
            return "opencodeGo.apiKey.\(id.uuidString)"
        case .grokAccountOAuthToken(let id):
            return "grok.oauth-token.\(id.uuidString)"
        }
    }
}

enum KeychainStore {
    private static let service = "app.quotabar.QuotaBar"

#if canImport(Security)
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
            let added = SecItemAdd(query as CFDictionary, nil)
            if added != errSecSuccess {
                QuotaBarLog.keychainError("Keychain add failed for \(account.rawValue): \(added)")
            }
            return
        }
        delete(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let added = SecItemAdd(query as CFDictionary, nil)
        if added != errSecSuccess {
            QuotaBarLog.keychainError("Keychain replace-add failed for \(account.rawValue): \(added)")
        }
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

    /// Drop per-UUID secrets that no longer belong to a saved account.
    static func reconcile(
        chatgptIDs: [UUID],
        grokIDs: [UUID],
        opencodeIDs: [UUID]
    ) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let items = out as? [[String: Any]] else { return }

        var keep: Set<String> = [
            KeychainAccount.cursorCookie.rawValue,
            KeychainAccount.cursorRefreshedSession.rawValue,
            KeychainAccount.chatgptCookie.rawValue,
            KeychainAccount.chatgptJSON.rawValue,
            KeychainAccount.glmAPIKey.rawValue,
            KeychainAccount.grokOAuthToken.rawValue
        ]
        for id in chatgptIDs {
            keep.insert(KeychainAccount.chatgptAccountCookie(id).rawValue)
            keep.insert(KeychainAccount.chatgptAccountJSON(id).rawValue)
        }
        for id in grokIDs {
            keep.insert(KeychainAccount.grokAccountOAuthToken(id).rawValue)
        }
        for id in opencodeIDs {
            keep.insert(KeychainAccount.opencodeGoAPIKey(id).rawValue)
        }

        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  isUUIDScoped(account),
                  !keep.contains(account)
            else { continue }
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(deleteQuery as CFDictionary)
        }
    }

    private static func baseQuery(_ account: KeychainAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]
    }
#else
    static func set(_ value: String?, account: KeychainAccount) {}
    static func get(_ account: KeychainAccount) -> String? { nil }
    static func delete(_ account: KeychainAccount) {}
    static func reconcile(chatgptIDs: [UUID], grokIDs: [UUID], opencodeIDs: [UUID]) {}
#endif

    static func isUUIDScoped(_ account: String) -> Bool {
        let prefixes = [
            "chatgpt.cookie.",
            "chatgpt.json.",
            "opencodeGo.apiKey.",
            "grok.oauth-token."
        ]
        for prefix in prefixes where account.hasPrefix(prefix) {
            let suffix = String(account.dropFirst(prefix.count))
            return UUID(uuidString: suffix) != nil
        }
        return false
    }
}
