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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let items = out as? [[String: Any]] else { return }

        let stored = items.compactMap { $0[kSecAttrAccount as String] as? String }
        for account in orphanedAccountNames(
            stored: stored,
            chatgptIDs: chatgptIDs,
            grokIDs: grokIDs,
            opencodeIDs: opencodeIDs
        ) {
            QuotaBarLog.keychainInfo(
                "Reconcile deleting orphan \(redactedAccountName(account)) (account name only, service \(service))"
            )
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

    /// Names reconcile may delete. Legacy unscoped keys are never included.
    /// A UUID is kept only when it belongs to an account of the provider in the key prefix.
    /// The caller must already have limited `stored` to this app's keychain service.
    static func orphanedAccountNames(
        stored: [String],
        chatgptIDs: [UUID],
        grokIDs: [UUID],
        opencodeIDs: [UUID]
    ) -> [String] {
        let chatgpt = Set(chatgptIDs)
        let grok = Set(grokIDs)
        let opencode = Set(opencodeIDs)
        return stored.filter { name in
            guard let parsed = parseScopedAccount(name) else { return false }
            switch parsed.provider {
            case .chatgpt:
                return !chatgpt.contains(parsed.id)
            case .grok:
                return !grok.contains(parsed.id)
            case .opencodeGo:
                return !opencode.contains(parsed.id)
            }
        }
    }

    static func redactedAccountName(_ account: String) -> String {
        guard let parsed = parseScopedAccount(account) else { return "unscoped" }
        let prefix = account.dropLast(parsed.id.uuidString.count)
        return prefix + String(parsed.id.uuidString.prefix(8)) + "…"
    }

    static func isUUIDScoped(_ account: String) -> Bool {
        parseScopedAccount(account) != nil
    }

    private enum ScopedProvider {
        case chatgpt
        case grok
        case opencodeGo
    }

    private static func parseScopedAccount(_ account: String) -> (provider: ScopedProvider, id: UUID)? {
        let prefixes: [(String, ScopedProvider)] = [
            ("chatgpt.cookie.", .chatgpt),
            ("chatgpt.json.", .chatgpt),
            ("opencodeGo.apiKey.", .opencodeGo),
            ("grok.oauth-token.", .grok)
        ]
        for (prefix, provider) in prefixes where account.hasPrefix(prefix) {
            let suffix = String(account.dropFirst(prefix.count))
            guard let id = UUID(uuidString: suffix) else { return nil }
            return (provider, id)
        }
        return nil
    }
}
