import Foundation

/// Shared HTTP status classification. 403 is not automatically an auth failure:
/// Vercel / HTML / Cloudflare checkpoints are network; JSON unauthenticated
/// markers (or HTTP 401) are auth; everything else stays a plain HTTP error.
enum HTTPClassify {
    enum Kind: Equatable {
        case ok
        case unauthorized
        case checkpoint
        case rateLimited
        case failure
    }

    static let checkpointMessage =
        "Usage is temporarily blocked by a security checkpoint. Try Refresh again."

    static func classify(status: Int, data: Data, contentType: String?) -> Kind {
        if isCheckpoint(status: status, data: data, contentType: contentType) {
            return .checkpoint
        }
        if isUnauthenticated(status: status, data: data, contentType: contentType) {
            return .unauthorized
        }
        if status == 429 {
            return .rateLimited
        }
        if (200...299).contains(status) {
            return .ok
        }
        return .failure
    }

    static func requireOK(_ response: HTTPURLResponse, data: Data, host: String) throws {
        switch classify(
            status: response.statusCode,
            data: data,
            contentType: response.value(forHTTPHeaderField: "Content-Type")
        ) {
        case .ok:
            return
        case .unauthorized:
            throw QuotaError.unauthorized("\(host) rejected the session (\(response.statusCode)).")
        case .checkpoint:
            throw QuotaError.network(checkpointMessage)
        case .rateLimited:
            throw QuotaError.http(429, snippet(data, fallback: "Rate limited by \(host)."))
        case .failure:
            throw QuotaError.http(response.statusCode, snippet(data, fallback: host))
        }
    }

    static func isCheckpoint(status: Int, data: Data, contentType: String?) -> Bool {
        guard status == 403 else { return false }
        if isVercelCheckpoint(data: data) { return true }
        let type = (contentType ?? "").lowercased()
        if type.contains("text/html") { return true }
        return looksLikeHTML(data) && !looksLikeJSON(data)
    }

    static func isVercelCheckpoint(data: Data) -> Bool {
        let text = String(data: data.prefix(4000), encoding: .utf8)?.lowercased() ?? ""
        return text.contains("vercel security checkpoint")
            || text.contains("security checkpoint")
            || text.contains("attention required")
            || text.contains("cf-error")
            || text.contains("cloudflare")
    }

    static func isUnauthenticated(status: Int, data: Data, contentType: String?) -> Bool {
        if isCheckpoint(status: status, data: data, contentType: contentType) {
            return false
        }
        if status == 401 {
            return true
        }
        if looksLikeJSON(data) || (contentType ?? "").lowercased().contains("json") {
            if let object = try? JSONWalk.object(from: data), isUnauthenticatedJSON(object) {
                return true
            }
        }
        return false
    }

    static func isUnauthenticatedJSON(_ object: [String: Any]) -> Bool {
        if object["error"] as? String == "not_authenticated" {
            return true
        }
        if object["shouldLogout"] as? Bool == true {
            return true
        }
        let haystack = [
            JSONWalk.string(object, keys: ["error", "code", "message"]) ?? ""
        ].joined(separator: " ").lowercased()
        let markers = [
            "not_authenticated",
            "not authenticated",
            "unauthenticated",
            "unauthorized",
            "invalid token",
            "token expired",
            "invalid_grant"
        ]
        return markers.contains { haystack.contains($0) }
    }

    static func looksLikeJSON(_ data: Data) -> Bool {
        guard let text = String(data: data.prefix(256), encoding: .utf8) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first == "{" || trimmed.first == "["
    }

    static func looksLikeHTML(_ data: Data) -> Bool {
        guard let text = String(data: data.prefix(256), encoding: .utf8) else { return false }
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html")
    }

    private static func snippet(_ data: Data, fallback: String) -> String {
        let text = String(data: data.prefix(180), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? fallback : text
    }
}
