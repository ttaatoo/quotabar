import Foundation

/// Read-only Codex CLI OAuth file. The CLI owns refresh and writes;
/// QuotaBar never updates `auth.json` and never starts a Codex OAuth dance.
enum CodexCLIAuth {
    struct Tokens: Equatable {
        var accessToken: String
        var accountId: String?
        var email: String?
        var planName: String?
    }

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

        if let idToken = nonEmpty(tokens["id_token"] as? String) {
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

        return Tokens(accessToken: access, accountId: accountId, email: email, planName: planName)
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
