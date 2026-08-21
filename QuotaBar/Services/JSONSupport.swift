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
            return (remaining(used: used), clamp(used))
        }
        if let remaining {
            return (clamp(remaining), remaining(used: remaining))
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
