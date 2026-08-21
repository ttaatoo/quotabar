import Foundation

/// Read-only SuperGrok / Grok CLI credentials. QuotaBar never writes or refreshes
/// `~/.grok/auth.json` (or `$GROK_HOME/auth.json`).
enum GrokAuth {
    struct Credentials: Equatable {
        var accessToken: String
        var email: String?
        var expiresAt: Date?
        var authMode: String?
        var teamId: String?
        var oidcScope: String?
        var source: Source

        var isExpired: Bool {
            guard let expiresAt else { return false }
            return Date() >= expiresAt
        }

        /// OIDC SuperGrok, then the raw `auth_mode`, then nothing.
        var planFallback: String? {
            if let scope = oidcScope, scope.hasPrefix(oidcScopePrefix) {
                return "SuperGrok"
            }
            switch authMode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "oidc":
                return "SuperGrok"
            case "session":
                return "session"
            case .some(let mode) where !mode.isEmpty:
                return authMode
            default:
                return nil
            }
        }
    }

    enum Source: Equatable {
        case authFile
        case pasted
        case environment
    }

    /// Top-level OIDC scope used by `grok login` for SuperGrok.
    static let oidcScopePrefix = "https://auth.x.ai::"
    /// Legacy/session scope used by older `grok login` flows.
    static let legacySessionScope = "https://accounts.x.ai/sign-in"

    static let signInHint =
        "Run `grok login` (writes ~/.grok/auth.json) or paste a SuperGrok bearer in Settings."

    static func grokHomeURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let custom = env["GROK_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok", isDirectory: true)
    }

    static func authFileURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        grokHomeURL(env: env).appendingPathComponent("auth.json")
    }

    /// Prefer a non-expired `auth.json`, then a pasted SuperGrok bearer, then `GROK_OAUTH_TOKEN`.
    /// Expired or missing files are not sent. QuotaBar never refreshes tokens.
    static func resolve(
        pasted: String?,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Credentials {
        if let file = loadAuthFile(env: env), !file.isExpired {
            return file
        }

        if let token = normalizedOAuthToken(pasted) {
            return Credentials(
                accessToken: token,
                email: nil,
                expiresAt: nil,
                authMode: "oidc",
                teamId: nil,
                oidcScope: nil,
                source: .pasted
            )
        }

        if let token = normalizedOAuthToken(env["GROK_OAUTH_TOKEN"]) {
            return Credentials(
                accessToken: token,
                email: nil,
                expiresAt: nil,
                authMode: "oidc",
                teamId: nil,
                oidcScope: nil,
                source: .environment
            )
        }

        if let file = loadAuthFile(env: env), file.isExpired {
            throw QuotaError.notSignedIn("Grok token expired. Run `grok login` again, or paste a SuperGrok bearer in Settings.")
        }

        if let pasted, !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           normalizedOAuthToken(pasted) == nil {
            throw QuotaError.notSignedIn(
                "That value is not a SuperGrok bearer. Run `grok login`, or paste a bearer — not an xai- management key or cookie."
            )
        }

        throw QuotaError.notSignedIn(signInHint)
    }

    static func loadAuthFile(env: [String: String] = ProcessInfo.processInfo.environment) -> Credentials? {
        let url = authFileURL(env: env)
        let path = url.path
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return parseAuthFile(data)
    }

    static func parseAuthFile(_ data: Data) -> Credentials? {
        guard let root = try? JSONWalk.object(from: data) else { return nil }

        var oidc: (scope: String, entry: [String: Any])?
        var legacy: (scope: String, entry: [String: Any])?
        for (scope, value) in root {
            guard let entry = value as? [String: Any] else { continue }
            guard let key = entry["key"] as? String, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            if scope.hasPrefix(oidcScopePrefix) {
                oidc = (scope, entry)
            } else if scope == legacySessionScope || scope.contains("/sign-in") {
                legacy = (scope, entry)
            }
        }

        let preferred = oidc ?? legacy
        guard let preferred else { return nil }
        guard let key = preferred.entry["key"] as? String else { return nil }
        let token = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }

        let email = JSONWalk.string(preferred.entry, keys: ["email"])
        return Credentials(
            accessToken: token,
            email: email,
            expiresAt: TimeFormatting.parseDate(preferred.entry["expires_at"]),
            authMode: JSONWalk.string(preferred.entry, keys: ["auth_mode"]),
            teamId: JSONWalk.string(preferred.entry, keys: ["team_id"]),
            oidcScope: preferred.scope,
            source: .authFile
        )
    }

    /// SuperGrok OAuth bearer only. Rejects `xai-` management keys and cookie-shaped values.
    static func normalizedOAuthToken(_ raw: String?) -> String? {
        var token = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if token.lowercased().hasPrefix("bearer ") {
            token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !token.isEmpty else { return nil }
        let lower = token.lowercased()
        if lower.hasPrefix("cookie:") { return nil }
        if lower.hasPrefix("xai-") { return nil }
        if token.contains("=") { return nil }
        return token
    }

    static func displayPlanName(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        let compact = trimmed.lowercased().filter(\.isLetter)
        switch compact {
        case "supergrokheavy", "heavy":
            return "SuperGrok Heavy"
        case "supergrok":
            return "SuperGrok"
        default:
            return trimmed
        }
    }
}
