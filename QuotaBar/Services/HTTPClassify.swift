import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
        if (200...299).contains(status) {
            // Cursor's api2 can return 200 with an exact not_authenticated / shouldLogout body.
            if isExactAuthJSON(data: data, contentType: contentType) {
                return .unauthorized
            }
            return .ok
        }
        if isCheckpoint(status: status, data: data, contentType: contentType) {
            return .checkpoint
        }
        if status == 401 || (status == 403 && isExactAuthJSON(data: data, contentType: contentType)) {
            return .unauthorized
        }
        if status == 429 {
            return .rateLimited
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
        if isJSONPayload(data, contentType: contentType) { return false }
        if isVercelCheckpoint(data: data) { return true }
        let type = (contentType ?? "").lowercased()
        if type.contains("text/html") { return true }
        return looksLikeHTML(data)
    }

    static func isVercelCheckpoint(data: Data) -> Bool {
        let text = String(data: data.prefix(4000), encoding: .utf8)?.lowercased() ?? ""
        return text.contains("vercel security checkpoint")
            || text.contains("security checkpoint")
            || text.contains("cf-error")
    }

    static func isUnauthenticated(status: Int, data: Data, contentType: String?) -> Bool {
        if (200...299).contains(status) || status == 403 {
            return isExactAuthJSON(data: data, contentType: contentType)
        }
        if status == 401 {
            return true
        }
        return false
    }

    /// `error` / `code` must equal a known auth marker. Message substrings such as
    /// "user unauthorized for this SKU" stay ordinary HTTP failures.
    static func isUnauthenticatedJSON(_ object: [String: Any]) -> Bool {
        if object["shouldLogout"] as? Bool == true {
            return true
        }
        let markers: Set<String> = [
            "not_authenticated",
            "unauthenticated",
            "unauthorized",
            "invalid_token",
            "invalid_grant",
            "token_expired"
        ]
        for key in ["error", "code"] {
            guard let raw = object[key] as? String else { continue }
            let normalized = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
            if markers.contains(normalized) { return true }
        }
        return false
    }

    static func isExactAuthJSON(data: Data, contentType: String?) -> Bool {
        guard isJSONPayload(data, contentType: contentType),
              let object = try? JSONWalk.object(from: data)
        else { return false }
        return isUnauthenticatedJSON(object)
    }

    static func isJSONPayload(_ data: Data, contentType: String?) -> Bool {
        looksLikeJSON(data) || (contentType ?? "").lowercased().contains("json")
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
