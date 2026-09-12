import Foundation

/// Read-only SuperGrok / Grok CLI credentials. QuotaBar never writes or refreshes
/// `~/.grok/auth.json` (or `$GROK_HOME/auth.json`). Extra accounts isolate login
/// by setting `GROK_HOME` to a private Application Support home; xAI documents
/// that variable as the home for auth.
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
        "Add a Grok account in Settings to sign in with the Grok CLI in your browser."

    static func grokHomeURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        defaultHomeURL(env: env)
    }

    static func defaultHomeURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let custom = env["GROK_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty {
            return expandedDirectory(custom)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok", isDirectory: true)
    }

    static func homeURL(path: String?) -> URL? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        return expandedDirectory(path)
    }

    static func authFileURL(home: URL? = nil, env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        (home ?? defaultHomeURL(env: env)).appendingPathComponent("auth.json")
    }

    static func isAmbientHome(_ url: URL) -> Bool {
        standardizedPath(url) == standardizedPath(defaultHomeURL())
    }

    static func isAmbientHomePath(_ path: String?) -> Bool {
        guard let url = homeURL(path: path) else { return false }
        return isAmbientHome(url)
    }

    static func managedHomesRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("QuotaBar", isDirectory: true)
            .appendingPathComponent("managed-grok-homes", isDirectory: true)
    }

    static func makeManagedHomeURL() -> URL {
        managedHomesRoot().appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    static func isManagedHome(_ url: URL) -> Bool {
        let root = standardizedPath(managedHomesRoot())
        let target = standardizedPath(url)
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return target.hasPrefix(prefix) && target != root
    }

    static func removeManagedHomeIfSafe(_ path: String?) {
        guard let home = homeURL(path: path), isManagedHome(home) else { return }
        let filePath = home.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: filePath) else { return }
        try? FileManager.default.removeItem(at: home)
    }

    /// Prefer a non-expired `auth.json` when allowed, then a pasted SuperGrok bearer,
    /// then `GROK_OAUTH_TOKEN` when allowed. Expired or missing files are not sent.
    /// QuotaBar never refreshes tokens.
    ///
    /// When `grokHomePath` is set, that home is read first and ambient `~/.grok`
    /// is not used unless the path is the ambient home.
    static func resolve(
        pasted: String?,
        useAmbientFile: Bool = true,
        allowEnvironment: Bool = true,
        grokHomePath: String? = nil,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Credentials {
        let scopedHome = homeURL(path: grokHomePath)
        let readAmbient = useAmbientFile && scopedHome == nil
        let fileHome = scopedHome
        if let fileHome, let file = loadAuthFile(home: fileHome), !file.isExpired {
            return file
        }
        if readAmbient, let file = loadAuthFile(env: env), !file.isExpired {
            return file
        }

        if let token = normalizedOAuthToken(pasted) {
            return Credentials(
                accessToken: token,
                email: AccountIdentity.fromToken(token),
                expiresAt: nil,
                authMode: "oidc",
                teamId: nil,
                oidcScope: nil,
                source: .pasted
            )
        }

        let allowEnvToken: Bool
        if !allowEnvironment {
            allowEnvToken = false
        } else if let scopedHome {
            allowEnvToken = isAmbientHome(scopedHome)
        } else {
            allowEnvToken = true
        }
        if allowEnvToken, let token = normalizedOAuthToken(env["GROK_OAUTH_TOKEN"]) {
            return Credentials(
                accessToken: token,
                email: AccountIdentity.fromToken(token),
                expiresAt: nil,
                authMode: "oidc",
                teamId: nil,
                oidcScope: nil,
                source: .environment
            )
        }

        if let fileHome, let file = loadAuthFile(home: fileHome), file.isExpired {
            throw QuotaError.notSignedIn("Grok token expired. Re-login this account in Settings.")
        }
        if readAmbient, let file = loadAuthFile(env: env), file.isExpired {
            throw QuotaError.notSignedIn("Grok token expired. Re-login this account in Settings.")
        }

        if let pasted, !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           normalizedOAuthToken(pasted) == nil {
            throw QuotaError.notSignedIn(
                "That value is not a SuperGrok bearer. Sign in with the Grok CLI, or paste a bearer, not an xai- management key or cookie."
            )
        }

        if scopedHome != nil {
            throw QuotaError.notSignedIn("No readable auth.json in this account’s Grok home. Re-login, or paste a SuperGrok bearer under Advanced.")
        }
        if !useAmbientFile {
            throw QuotaError.notSignedIn("Sign in with the Grok CLI, or paste a SuperGrok bearer under Advanced.")
        }
        throw QuotaError.notSignedIn(signInHint)
    }

    static func loadAuthFile(
        home: URL? = nil,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> Credentials? {
        let url = authFileURL(home: home, env: env)
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return parseAuthFile(data)
    }

    private static func expandedDirectory(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    private static func standardizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
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
            ?? AccountIdentity.fromJSON(preferred.entry)
            ?? AccountIdentity.fromToken(token)
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
