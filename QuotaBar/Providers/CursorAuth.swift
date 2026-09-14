import Foundation
import SQLite3

enum CursorAuth {
    /// Popover / Settings hint. Cookie paste is Advanced-only.
    static let signInHint =
        "Open Cursor.app and sign in, then Refresh. Leave the optional Settings cookie empty unless you paste a fresh WorkosCursorSessionToken."

    static let notSignedInMessage =
        "No Cursor session found. Open Cursor.app and sign in, then Refresh."

    static let unauthenticatedMessage =
        "cursor.com rejected the local session. Re-sign in inside Cursor.app, leave the optional cookie empty, then Refresh."

    static let refreshFailedMessage =
        "cursor.com rejected the local session (refresh failed). Re-sign in inside Cursor.app, leave the optional cookie empty, then Refresh."

    static let noRefreshTokenMessage =
        "cursor.com rejected the local session (no refresh token). Re-sign in inside Cursor.app, leave the optional cookie empty, then Refresh."

    /// Public Cursor desktop client id used by `POST https://api2.cursor.sh/oauth/token`.
    /// This is Cursor.app's own client, not a QuotaBar-registered OAuth app.
    static let oauthClientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"
    static let defaultRefreshURL = URL(string: "https://api2.cursor.sh/oauth/token")!

    static func rejectedSessionMessage(status: Int) -> String {
        "cursor.com rejected the local session (\(status)). Re-sign in inside Cursor.app, leave the optional cookie empty, then Refresh."
    }

    static func isRejectedSessionMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("rejected")
            || message.contains("403")
            || message.contains("401")
            || lower.contains("not authenticated")
    }

    static let defaultDBPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")

    static let agentAuthPaths: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/cursor/auth.json"),
            home.appendingPathComponent(".config/cursor/auth.json"),
            home.appendingPathComponent(".cursor/auth.json")
        ]
    }()

    enum SessionKind: Equatable, Sendable {
        case pasted
        case ambient
    }

    struct ResolvedSession: Equatable, Sendable {
        var cookie: String
        var kind: SessionKind

        var allowsRefresh: Bool { kind == .ambient }
    }

    struct RefreshPayload: Equatable, Sendable {
        var accessToken: String
        var refreshToken: String?
        var shouldLogout: Bool
    }

    static func resolveCookie(pasted: String?) throws -> String {
        try resolveSession(pasted: pasted).cookie
    }

    /// Pasted Advanced cookie wins and is never replaced by an ambient refresh.
    static func resolveSession(pasted: String?) throws -> ResolvedSession {
        if let pasted, let cookie = normalizePastedCookie(pasted) {
            return ResolvedSession(cookie: cookie, kind: .pasted)
        }
        if let token = resolveAmbientAccessToken() {
            return ResolvedSession(cookie: cookie(fromAccessToken: token), kind: .ambient)
        }
        throw QuotaError.notSignedIn(notSignedInMessage)
    }

    static func cookie(fromAccessToken token: String) -> String {
        if token.contains("WorkosCursorSessionToken=") {
            return normalizePastedCookie(token) ?? token
        }
        if token.contains("%3A%3A") || token.contains("::") {
            let value = token
                .replacingOccurrences(of: "WorkosCursorSessionToken=", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "WorkosCursorSessionToken=\(value.contains("%3A%3A") ? value : value.replacingOccurrences(of: "::", with: "%3A%3A"))"
        }
        if let userID = JWT.trailingSubject(token) {
            return "WorkosCursorSessionToken=\(userID)%3A%3A\(token)"
        }
        return "WorkosCursorSessionToken=\(token)"
    }

    static func normalizePastedCookie(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("cookie:") {
            return normalizePastedCookie(String(trimmed.dropFirst(7)))
        }

        if trimmed.contains("WorkosCursorSessionToken=") {
            let parts = trimmed.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            if let token = parts.first(where: { $0.hasPrefix("WorkosCursorSessionToken=") }) {
                return token
            }
        }

        if trimmed.contains("%3A%3A") || trimmed.contains("::") {
            let encoded = trimmed.replacingOccurrences(of: "::", with: "%3A%3A")
            return encoded.hasPrefix("WorkosCursorSessionToken=")
                ? encoded
                : "WorkosCursorSessionToken=\(encoded)"
        }

        if JWT.payload(trimmed) != nil {
            return cookie(fromAccessToken: trimmed)
        }

        return "WorkosCursorSessionToken=\(trimmed)"
    }

    static func emailFromSessionCookie(_ cookie: String) -> String? {
        for component in cookie.split(separator: ";") {
            let pair = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            let name = pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard name == "WorkosCursorSessionToken" else { continue }
            let encoded = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = encoded.removingPercentEncoding ?? encoded
            let token = value.components(separatedBy: "::").last ?? value
            if let payload = JWT.payload(token) {
                return CodexCLIAuth.email(from: payload)
            }
        }
        if let payload = JWT.payload(cookie) {
            return CodexCLIAuth.email(from: payload)
        }
        return nil
    }

    /// Prefer a QuotaBar-refreshed access token while Cursor's store still has
    /// the stale token we replaced. If Cursor.app itself refreshed or the user
    /// re-signed in, drop our cache and use the local token.
    static func resolveAmbientAccessToken() -> String? {
        let local = readLocalTokens()
        let cached = SessionCache.load()
        if let localAccess = local.accessToken, let cached {
            if localAccess == cached.sourceAccessToken || localAccess == cached.accessToken {
                return cached.accessToken
            }
            SessionCache.clear()
            return localAccess
        }
        return cached?.accessToken ?? local.accessToken
    }

    static func readLocalAccessToken() -> String? {
        readLocalTokens().accessToken
    }

    /// Exchange `cursorAuth/refreshToken` at Cursor's desktop token endpoint.
    /// Persists the new access token in memory + QuotaBar Keychain only —
    /// never writes `state.vscdb` or `~/.cursor`.
    static func refreshAmbientSession() async throws -> String {
        try await CursorRefreshGate.shared.run {
            try await performRefresh()
        }
    }

    /// Accepts both snake_case (`access_token`) and camelCase (`accessToken`).
    static func parseRefreshResponse(_ object: [String: Any]) -> RefreshPayload {
        let access = JSONWalk.string(object, keys: ["access_token", "accessToken"]) ?? ""
        let refresh = JSONWalk.string(object, keys: ["refresh_token", "refreshToken"])
        let shouldLogout: Bool
        if let value = object["shouldLogout"] as? Bool {
            shouldLogout = value
        } else if let value = object["should_logout"] as? Bool {
            shouldLogout = value
        } else {
            shouldLogout = false
        }
        return RefreshPayload(accessToken: access, refreshToken: refresh, shouldLogout: shouldLogout)
    }

    static func readLocalTokens() -> LocalTokens {
        if FileManager.default.fileExists(atPath: fileSystemPath(defaultDBPath)) {
            let tokens = readTokensFromSQLite(defaultDBPath)
            if tokens.accessToken != nil || tokens.refreshToken != nil {
                return tokens
            }
        }
        for url in agentAuthPaths where FileManager.default.fileExists(atPath: fileSystemPath(url)) {
            let tokens = readAgentTokens(url)
            if tokens.accessToken != nil || tokens.refreshToken != nil {
                return tokens
            }
        }
        return LocalTokens(accessToken: nil, refreshToken: nil)
    }

    struct LocalTokens: Equatable, Sendable {
        var accessToken: String?
        var refreshToken: String?
    }

    /// Copies the live Cursor DB (and WAL/SHM) then reads auth keys read-only.
    static func readTokenFromSQLite(_ url: URL) -> String? {
        readTokensFromSQLite(url).accessToken
    }

    private static func performRefresh() async throws -> String {
        let local = readLocalTokens()
        let cached = SessionCache.load()
        guard let refreshToken = refreshTokenForRefresh(local: local, cached: cached) else {
            throw QuotaError.unauthorized(noRefreshTokenMessage)
        }

        let url = refreshURL()
        let (data, response) = try await HTTPClient.postJSON(
            url: url,
            body: [
                "grant_type": "refresh_token",
                "client_id": oauthClientID,
                "refresh_token": refreshToken
            ],
            timeout: RefreshWork.oauthTimeout
        )
        if response.statusCode == 401 || response.statusCode == 403 {
            SessionCache.clear()
            throw QuotaError.unauthorized(refreshFailedMessage)
        }
        try HTTPClient.requireOK(response, data: data, host: url.host ?? "api2.cursor.sh")

        let object = try JSONWalk.object(from: data)
        let parsed = parseRefreshResponse(object)
        if parsed.shouldLogout || parsed.accessToken.isEmpty {
            SessionCache.clear()
            throw QuotaError.unauthorized(refreshFailedMessage)
        }

        let session = CachedSession(
            accessToken: parsed.accessToken,
            refreshToken: parsed.refreshToken ?? refreshToken,
            sourceAccessToken: local.accessToken ?? cached?.sourceAccessToken
        )
        SessionCache.save(session)
        return cookie(fromAccessToken: parsed.accessToken)
    }

    private static func refreshTokenForRefresh(local: LocalTokens, cached: CachedSession?) -> String? {
        if let cachedRefresh = cached?.refreshToken,
           (cached?.sourceAccessToken == local.accessToken
            || local.accessToken == nil
            || local.accessToken == cached?.accessToken) {
            return cachedRefresh
        }
        return local.refreshToken ?? cached?.refreshToken
    }

    private static func refreshURL() -> URL {
        let override = ProcessInfo.processInfo.environment["CURSOR_REFRESH_TOKEN_URL_OVERRIDE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !override.isEmpty, let url = URL(string: override) {
            return url
        }
        return defaultRefreshURL
    }

    private static func readAgentTokens(_ url: URL) -> LocalTokens {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return LocalTokens(accessToken: nil, refreshToken: nil)
        }
        return LocalTokens(
            accessToken: nonEmpty(object["accessToken"] as? String)
                ?? nonEmpty(object["access_token"] as? String),
            refreshToken: nonEmpty(object["refreshToken"] as? String)
                ?? nonEmpty(object["refresh_token"] as? String)
        )
    }

    private static func readTokensFromSQLite(_ url: URL) -> LocalTokens {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotabar-cursor-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let dest = tempDir.appendingPathComponent("state.vscdb")
            try FileManager.default.copyItem(at: url, to: dest)
            for suffix in ["-wal", "-shm"] {
                let side = URL(fileURLWithPath: fileSystemPath(url) + suffix)
                if FileManager.default.fileExists(atPath: fileSystemPath(side)) {
                    try FileManager.default.copyItem(at: side, to: URL(fileURLWithPath: fileSystemPath(dest) + suffix))
                }
            }
            defer { try? FileManager.default.removeItem(at: tempDir) }
            return queryAuthTokens(at: dest)
        } catch {
            return queryAuthTokens(at: url)
        }
    }

    private static func fileSystemPath(_ url: URL) -> String {
        url.path(percentEncoded: false)
    }

    private static func queryAuthTokens(at url: URL) -> LocalTokens {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let status = url.withUnsafeFileSystemRepresentation { cPath -> Int32 in
            guard let cPath else { return SQLITE_CANTOPEN }
            return sqlite3_open_v2(cPath, &db, flags, nil)
        }
        guard status == SQLITE_OK, let db else {
            if db != nil { sqlite3_close(db) }
            return LocalTokens(accessToken: nil, refreshToken: nil)
        }
        defer { sqlite3_close(db) }

        return LocalTokens(
            accessToken: queryItem(db: db, key: "cursorAuth/accessToken"),
            refreshToken: queryItem(db: db, key: "cursorAuth/refreshToken")
        )
    }

    private static func queryItem(db: OpaquePointer, key: String) -> String? {
        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = ?1 LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, key, -1, transient)

        guard sqlite3_step(stmt) == SQLITE_ROW, let cString = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        return nonEmpty(String(cString: cString))
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

/// In-memory + Keychain cache of a QuotaBar-refreshed Cursor session.
/// Never written to `state.vscdb` (Cursor may hold that file locked).
private enum SessionCache {
    private static let lock = NSLock()
    private static var memory: CachedSession?

    static func load() -> CachedSession? {
        lock.lock()
        defer { lock.unlock() }
        if let memory {
            return memory
        }
        let loaded = readKeychain()
        memory = loaded
        return loaded
    }

    static func save(_ session: CachedSession) {
        lock.lock()
        defer { lock.unlock() }
        memory = session
        if let encoded = session.encoded {
            KeychainStore.set(encoded, account: .cursorRefreshedSession)
        }
    }

    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        memory = nil
        KeychainStore.delete(.cursorRefreshedSession)
    }

    private static func readKeychain() -> CachedSession? {
        guard let raw = KeychainStore.get(.cursorRefreshedSession) else { return nil }
        return CachedSession.decode(raw)
    }
}

private struct CachedSession: Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var sourceAccessToken: String?

    var encoded: String? {
        var object: [String: String] = ["accessToken": accessToken]
        if let refreshToken {
            object["refreshToken"] = refreshToken
        }
        if let sourceAccessToken {
            object["sourceAccessToken"] = sourceAccessToken
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text
    }

    static func decode(_ raw: String) -> CachedSession? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let access = (object["accessToken"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !access.isEmpty else { return nil }
        let refresh = (object["refreshToken"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let source = (object["sourceAccessToken"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CachedSession(
            accessToken: access,
            refreshToken: (refresh?.isEmpty == false) ? refresh : nil,
            sourceAccessToken: (source?.isEmpty == false) ? source : nil
        )
    }
}

/// Coalesce concurrent 403-driven refreshes so a rotating refresh token is
/// not spent twice in the same poll.
private actor CursorRefreshGate {
    static let shared = CursorRefreshGate()
    private var inFlight: Task<String, Error>?

    func run(_ work: @Sendable @escaping () async throws -> String) async throws -> String {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { try await work() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
