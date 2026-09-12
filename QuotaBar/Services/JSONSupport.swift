import Foundation

enum JSONNumber {
    static func double(from raw: Any?) -> Double? {
        switch raw {
        case let value as Double: return value.isFinite ? value : nil
        case let value as Float: return Double(value).isFinite ? Double(value) : nil
        case let value as Int: return Double(value)
        case let value as Int64: return Double(value)
        case let value as NSNumber: return value.doubleValue
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "%", with: "")
            return Double(trimmed)
        default:
            return nil
        }
    }

    static func int(from raw: Any?) -> Int? {
        guard let value = double(from: raw) else { return nil }
        return Int(value.rounded())
    }
}

enum JSONWalk {
    static func object(from data: Data) throws -> [String: Any] {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let object = json as? [String: Any] else {
            throw QuotaError.schema("Expected a JSON object.")
        }
        return object
    }

    static func string(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    static func nested(_ object: [String: Any], path: [String]) -> Any? {
        var current: Any = object
        for key in path {
            if let dict = current as? [String: Any], let next = dict[key] {
                current = next
            } else {
                return nil
            }
        }
        return current
    }

    /// Walks a JSON tree and yields every dictionary, with the nearest key name.
    static func dictionaries(in value: Any, parentKey: String? = nil) -> [(key: String?, object: [String: Any])] {
        var results: [(String?, [String: Any])] = []
        walk(value, parentKey: parentKey, into: &results)
        return results
    }

    private static func walk(_ value: Any, parentKey: String?, into results: inout [(String?, [String: Any])]) {
        if let object = value as? [String: Any] {
            results.append((parentKey, object))
            for (key, child) in object {
                walk(child, parentKey: key, into: &results)
            }
        } else if let array = value as? [Any] {
            for child in array {
                walk(child, parentKey: parentKey, into: &results)
            }
        }
    }
}

enum JWT {
    static func payload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func trailingSubject(_ token: String) -> String? {
        guard let payload = payload(token), let sub = payload["sub"] as? String else { return nil }
        if let last = sub.split(separator: "|").map(String.init).last, !last.isEmpty {
            return last
        }
        return sub.isEmpty ? nil : sub
    }

    static func expiration(_ token: String) -> Date? {
        guard let payload = payload(token),
              let exp = JSONNumber.double(from: payload["exp"])
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// Unknown `exp` is treated as still usable so callers can try the token.
    static func isExpired(_ token: String, skew: TimeInterval = 60) -> Bool {
        guard let expiration = expiration(token) else { return false }
        return Date().addingTimeInterval(skew) >= expiration
    }
}

/// Display identity for a provider card. Prefers a real email, then a
/// username / handle, then a short account id. Never invents an address.
enum AccountIdentity {
    static func fromJSON(_ value: Any) -> String? {
        for (_, object) in JSONWalk.dictionaries(in: value) {
            if let email = CodexCLIAuth.email(from: object) {
                return email
            }
        }
        for (_, object) in JSONWalk.dictionaries(in: value) {
            if let handle = usableHandle(JSONWalk.string(object, keys: [
                "username", "userName", "user_name", "nickName", "nickname",
                "displayName", "display_name", "preferred_username", "handle", "login"
            ])) {
                return handle
            }
        }
        for (_, object) in JSONWalk.dictionaries(in: value) {
            if let id = usableHandle(JSONWalk.string(object, keys: [
                "userId", "user_id", "uid", "accountId", "account_id"
            ])) {
                return shortenID(id)
            }
        }
        return nil
    }

    static func fromToken(_ token: String) -> String? {
        guard let payload = JWT.payload(token) else { return nil }
        if let email = CodexCLIAuth.email(from: payload) {
            return email
        }
        if let handle = usableHandle(JSONWalk.string(payload, keys: [
            "preferred_username", "username", "name", "handle", "nickname"
        ])) {
            return handle
        }
        if let sub = JWT.trailingSubject(token) {
            return shortenID(sub)
        }
        return nil
    }

    static func resolve(json: Any, token: String?) -> String? {
        fromJSON(json) ?? token.flatMap(fromToken)
    }

    static func usableHandle(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed.count <= 80, !trimmed.contains("\n") else { return nil }
        let lower = trimmed.lowercased()
        let banned: Set<String> = [
            "pro", "free", "plus", "max", "lite", "prolite", "unknown",
            "null", "undefined", "none", "user", "account", "glm", "coding"
        ]
        if banned.contains(lower) { return nil }
        if lower.hasPrefix("{") || lower.hasPrefix("[") { return nil }
        return trimmed
    }

    static func shortenID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= 18 { return trimmed }
        if trimmed.contains("@") { return usableHandle(trimmed) }
        return String(trimmed.prefix(8)) + "…"
    }
}

enum Percent {
    static func remaining(used: Double) -> Double {
        max(0, 100 - used)
    }

    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return value
    }

    static func fromRemainingUsed(remaining: Double?, used: Double?, limit: Double?) -> (remaining: Double, used: Double)? {
        if let remaining, let used {
            return (clamp(remaining), clamp(used))
        }
        if let remaining, let limit, limit > 0 {
            return (clamp((remaining / limit) * 100), clamp(((limit - remaining) / limit) * 100))
        }
        if let used, let limit, limit > 0 {
            return (clamp(((limit - used) / limit) * 100), clamp((used / limit) * 100))
        }
        if let used {
            return (Percent.remaining(used: used), clamp(used))
        }
        if let remaining {
            return (clamp(remaining), Percent.remaining(used: remaining))
        }
        return nil
    }

    static func parseMessage(_ message: String) -> Double? {
        guard let percentIndex = message.firstIndex(of: "%") else { return nil }
        let before = message[..<percentIndex]
        var start = before.startIndex
        if let idx = before.lastIndex(where: { !$0.isNumber && $0 != "." }) {
            start = before.index(after: idx)
        }
        return Double(before[start...])
    }
}

enum TitleCase {
    static func words(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }
        return trimmed
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { part in
                let lower = part.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }
}
