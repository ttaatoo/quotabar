import Foundation

/// Reads Codex CLI `auth.json`. QuotaBar never starts a ChatGPT OAuth app.
/// For a home we already have, an expired access token is refreshed with the
/// same public Codex client + `refresh_token` the CLI uses, then written back
/// (refresh tokens rotate). That is required for a second managed Codex home:
/// the CLI does not poll those files, so a stale `access_token` 401s forever.
enum CodexCLIAuth {
    static let oauthClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let defaultRefreshURL = URL(string: "https://auth.openai.com/oauth/token")!

    struct Tokens: Equatable, Sendable {
        var accessToken: String
        var refreshToken: String?
        var idToken: String?
        var accountId: String?
        var email: String?
        var planName: String?
    }

    private static let persistLock = NSLock()

    static func defaultHomeURL() -> URL {
        let env = ProcessInfo.processInfo.environment["CODEX_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !env.isEmpty {
            return expandedDirectory(env)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    static func homeURL(path: String?) -> URL? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        return expandedDirectory(path)
    }

    static func authFileURL(home: URL) -> URL {
        home.appendingPathComponent("auth.json")
    }

    static func isAmbientHome(_ url: URL) -> Bool {
        standardizedPath(url) == standardizedPath(defaultHomeURL())
    }

    static func read(home: URL? = nil) -> Tokens? {
        let homeURL = home ?? defaultHomeURL()
        let url = authFileURL(home: homeURL)
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: url),
              let object = try? JSONWalk.object(from: data)
        else { return nil }

        let tokens = object["tokens"] as? [String: Any] ?? [:]
        guard let access = nonEmpty(tokens["access_token"] as? String) else { return nil }

        var accountId = nonEmpty(tokens["account_id"] as? String)
        var email: String?
        var planName: String?
        let refresh = nonEmpty(tokens["refresh_token"] as? String)
        let idToken = nonEmpty(tokens["id_token"] as? String)

        if let idToken {
            let identity = identityFromJWT(idToken)
            if email == nil { email = identity.email }
            if accountId == nil { accountId = identity.accountId }
            if planName == nil { planName = identity.planName }
        }
        if email == nil || accountId == nil || planName == nil {
            let identity = identityFromJWT(access)
            if email == nil { email = identity.email }
            if accountId == nil { accountId = identity.accountId }
            if planName == nil { planName = identity.planName }
        }

        return Tokens(
            accessToken: access,
            refreshToken: refresh,
            idToken: idToken,
            accountId: accountId,
            email: email,
            planName: planName
        )
    }

    /// Fresh access token, refreshing when the JWT is expired or `forceRefresh` is set.
    static func resolve(home: URL?, forceRefresh: Bool = false) async throws -> Tokens {
        let homeURL = home ?? defaultHomeURL()
        guard let tokens = read(home: homeURL) else {
            throw QuotaError.notSignedIn("No readable auth.json was found in that Codex home.")
        }
        let expired = JWT.isExpired(tokens.accessToken)
        if !forceRefresh && !expired {
            return tokens
        }
        guard let refreshToken = tokens.refreshToken else {
            if expired {
                throw QuotaError.unauthorized(
                    "This account's Codex access token expired and auth.json has no refresh token. Re-login this account in Settings — other accounts stay."
                )
            }
            return tokens
        }
        do {
            return try await RefreshWork.withTimeout(seconds: RefreshWork.oauthTimeout) {
                try await refreshAndPersist(tokens: tokens, refreshToken: refreshToken, home: homeURL)
            }
        } catch {
            if expired || forceRefresh {
                throw error
            }
            return tokens
        }
    }

    private static func refreshAndPersist(
        tokens: Tokens,
        refreshToken: String,
        home: URL
    ) async throws -> Tokens {
        let url = refreshURL()
        let (data, response) = try await HTTPClient.postJSON(
            url: url,
            body: [
                "client_id": oauthClientID,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken
            ],
            timeout: RefreshWork.oauthTimeout
        )
        if response.statusCode == 401 || response.statusCode == 403 {
            let object = (try? JSONWalk.object(from: data)) ?? [:]
            let code = JSONWalk.string(object, keys: ["error", "code"]) ?? ""
            let suffix = code.isEmpty ? "" : " (\(code))"
            throw QuotaError.unauthorized(
                "This account's Codex login expired\(suffix). Re-login this account in Settings — other accounts stay."
            )
        }
        try HTTPClient.requireOK(response, data: data, host: url.host ?? "auth.openai.com")
        let object = try JSONWalk.object(from: data)
        guard let access = nonEmpty(object["access_token"] as? String) else {
            throw QuotaError.schema("Codex token refresh returned no access_token.")
        }

        var next = tokens
        next.accessToken = access
        if let rotated = nonEmpty(object["refresh_token"] as? String) {
            next.refreshToken = rotated
        }
        if let idToken = nonEmpty(object["id_token"] as? String) {
            next.idToken = idToken
        }
        let identity = identityFromJWT(next.idToken ?? access)
        if next.email == nil { next.email = identity.email }
        if next.accountId == nil { next.accountId = identity.accountId }
        if next.planName == nil { next.planName = identity.planName }

        persistLock.lock()
        defer { persistLock.unlock() }
        try writeRefreshed(home: home, tokens: next)
        return next
    }

    private static func refreshURL() -> URL {
        let override = ProcessInfo.processInfo.environment["CODEX_REFRESH_TOKEN_URL_OVERRIDE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !override.isEmpty, let url = URL(string: override) {
            return url
        }
        return defaultRefreshURL
    }

    /// Atomically update `tokens` + `last_refresh`, preserving other auth.json keys.
    private static func writeRefreshed(home: URL, tokens: Tokens) throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let url = authFileURL(home: home)
        var object: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
           let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object = existing
        }
        var tokenObject = object["tokens"] as? [String: Any] ?? [:]
        tokenObject["access_token"] = tokens.accessToken
        if let refresh = tokens.refreshToken {
            tokenObject["refresh_token"] = refresh
        }
        if let idToken = tokens.idToken {
            tokenObject["id_token"] = idToken
        }
        if let accountId = tokens.accountId {
            tokenObject["account_id"] = accountId
        }
        object["tokens"] = tokenObject
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        object["last_refresh"] = formatter.string(from: Date())

        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: [.atomic])
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path(percentEncoded: false)
        )
    }

    static func identityFromJWT(_ token: String) -> (email: String?, accountId: String?, planName: String?) {
        guard let payload = JWT.payload(token) else {
            return (nil, nil, nil)
        }
        let email = email(from: payload)
        var accountId = JSONWalk.string(payload, keys: ["chatgpt_account_id", "account_id", "chatgptAccountId"])
        var planName: String?
        if let auth = payload["https://api.openai.com/auth"] as? [String: Any] {
            if accountId == nil {
                accountId = JSONWalk.string(auth, keys: ["chatgpt_account_id", "account_id"])
            }
            if let plan = JSONWalk.string(auth, keys: ["chatgpt_plan_type", "plan_type", "planType"]) {
                planName = humanPlanName(plan)
            }
        }
        if planName == nil, let plan = JSONWalk.string(payload, keys: ["chatgpt_plan_type", "plan_type", "planType"]) {
            planName = humanPlanName(plan)
        }
        return (email, accountId, planName)
    }

    static func email(from object: [String: Any]) -> String? {
        let direct = JSONWalk.string(object, keys: [
            "email", "email_address", "emailAddress", "user_email", "userEmail", "accountEmail"
        ])
        if let email = usableEmail(direct) {
            return email
        }
        if let preferred = JSONWalk.string(object, keys: ["preferred_username"]),
           let email = usableEmail(preferred) {
            return email
        }
        if let user = object["user"] as? [String: Any],
           let email = email(from: user) {
            return email
        }
        if let account = object["account"] as? [String: Any],
           let email = email(from: account) {
            return email
        }
        return nil
    }

    static func usableEmail(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.contains("@"),
              !trimmed.contains(" ")
        else { return nil }
        return trimmed
    }

    static func humanPlanName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "chatgptplusplan", "plus": return "Plus"
        case "chatgptproplan", "pro": return "Pro"
        case "chatgptproliteplan", "prolite", "pro_lite", "pro-lite": return "Prolite"
        case "chatgptteamplan", "team": return "Team"
        case "chatgptenterpriseplan", "enterprise": return "Enterprise"
        case "free", "chatgptfreeplan": return "Free"
        default:
            return TitleCase.words(
                raw.replacingOccurrences(of: "chatgpt", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "plan", with: "", options: .caseInsensitive)
            )
        }
    }

    static func managedHomesRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("QuotaBar", isDirectory: true)
            .appendingPathComponent("managed-codex-homes", isDirectory: true)
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

    private static func expandedDirectory(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    private static func standardizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
