import Foundation
import SQLite3

enum CursorAuth {
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

    static func resolveCookie(pasted: String?) throws -> String {
        if let pasted, let cookie = normalizePastedCookie(pasted) {
            return cookie
        }
        if let token = readLocalAccessToken() {
            return cookie(fromAccessToken: token)
        }
        throw QuotaError.notSignedIn("No Cursor session found. Sign in to Cursor.app or paste a WorkosCursorSessionToken in Settings.")
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

    static func readLocalAccessToken() -> String? {
        if FileManager.default.fileExists(atPath: fileSystemPath(defaultDBPath)),
           let token = readTokenFromSQLite(defaultDBPath),
           !token.isEmpty {
            return token
        }
        for url in agentAuthPaths where FileManager.default.fileExists(atPath: fileSystemPath(url)) {
            if let token = readAgentToken(url), !token.isEmpty {
                return token
            }
        }
        return nil
    }

    private static func readAgentToken(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["accessToken"] as? String
    }

    /// Copies the live Cursor DB (and WAL/SHM) then reads `cursorAuth/accessToken` read-only.
    static func readTokenFromSQLite(_ url: URL) -> String? {
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
            return queryAccessToken(at: dest)
        } catch {
            return queryAccessToken(at: url)
        }
    }

    private static func fileSystemPath(_ url: URL) -> String {
        url.path(percentEncoded: false)
    }

    private static func queryAccessToken(at url: URL) -> String? {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let status = url.withUnsafeFileSystemRepresentation { cPath -> Int32 in
            guard let cPath else { return SQLITE_CANTOPEN }
            return sqlite3_open_v2(cPath, &db, flags, nil)
        }
        guard status == SQLITE_OK, let db else {
            if db != nil { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = ?1 LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        let key = "cursorAuth/accessToken"
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, key, -1, transient)

        guard sqlite3_step(stmt) == SQLITE_ROW, let cString = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        let value = String(cString: cString).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
