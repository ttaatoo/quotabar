import Foundation

enum ChatGPTClient {
    private static let sessionCookieName = "__Secure-next-auth.session-token"

    private static let whamURLs = [
        "https://chatgpt.com/backend-api/wham/usage",
        "https://chat.openai.com/backend-api/wham/usage"
    ]

    private static let conversationLimitURLs = [
        "https://chatgpt.com/backend-api/conversation_limit",
        "https://chatgpt.com/public-api/conversation_limit"
    ]

    static func fetch(cookie pasted: String?, pastedJSON: String?, now: Date = Date()) async throws -> UsageSnapshot {
        let cookie = normalizeCookie(pasted)
        var lastError: Error?
        var cookieIdentity: Identity?
        var cookieUnauthorized = false
        var codexTokens: CodexCLIAuth.Tokens?
        var triedCodexAuth = false
        var gotJSONWithoutWindows = false

        if let cookie {
            do {
                let identity = try await fetchSession(cookie: cookie)
                cookieIdentity = identity
                do {
                    if let snapshot = try await requestWhamUsage(
                        accessToken: identity.accessToken,
                        cookie: cookie,
                        accountId: identity.accountId,
                        email: identity.email,
                        planName: identity.planName,
                        now: now
                    ) {
                        return snapshot
                    }
                    gotJSONWithoutWindows = true
                } catch let error as QuotaError where error.isAuthFailure {
                    cookieUnauthorized = true
                    lastError = error
                } catch {
                    lastError = error
                }
            } catch let error as QuotaError where error.isAuthFailure {
                cookieUnauthorized = true
                lastError = error
            } catch {
                lastError = error
            }
        }

        if cookie == nil || cookieUnauthorized {
            triedCodexAuth = true
            if let tokens = CodexCLIAuth.read() {
                codexTokens = tokens
                do {
                    if let snapshot = try await requestWhamUsage(
                        accessToken: tokens.accessToken,
                        cookie: nil,
                        accountId: tokens.accountId,
                        email: tokens.email ?? cookieIdentity?.email,
                        planName: tokens.planName ?? cookieIdentity?.planName,
                        now: now
                    ) {
                        return snapshot
                    }
                    gotJSONWithoutWindows = true
                } catch let error as QuotaError where error.isAuthFailure {
                    lastError = error
                } catch {
                    lastError = error
                }
            }
        }

        let fallbackToken = cookieIdentity?.accessToken ?? codexTokens?.accessToken
        let fallbackCookie = cookieIdentity == nil ? nil : cookie
        let fallbackAccountId = cookieIdentity?.accountId ?? codexTokens?.accountId
        let fallbackEmail = cookieIdentity?.email ?? codexTokens?.email
        var fallbackPlan = cookieIdentity?.planName ?? codexTokens?.planName

        if let fallbackToken {
            if fallbackPlan == nil {
                fallbackPlan = try? await fetchPlanName(accessToken: fallbackToken, accountId: fallbackAccountId)
            }
            do {
                if let snapshot = try await fetchConversationLimit(
                    accessToken: fallbackToken,
                    cookie: fallbackCookie,
                    accountId: fallbackAccountId,
                    email: fallbackEmail,
                    planName: fallbackPlan,
                    now: now
                ) {
                    return snapshot
                }
                gotJSONWithoutWindows = true
            } catch {
                lastError = error
            }
        }

        if let pastedJSON, let snapshot = try? parsePastedOrOfficial(pastedJSON, fetchedAt: now, source: .pastedJSON) {
            return snapshot
        }

        if let lastError = lastError as? QuotaError, lastError.isAuthFailure, !gotJSONWithoutWindows {
            throw lastError
        }

        if cookie == nil && codexTokens == nil {
            if let pastedJSON {
                return try parsePastedOrOfficial(pastedJSON, fetchedAt: now, source: .pastedJSON)
            }
            throw QuotaError.notSignedIn(
                "Run `codex login` (QuotaBar reads ~/.codex/auth.json the same way CodexBar does), sign in to ChatGPT in Settings, or paste a session cookie / usage JSON."
            )
        }

        if let lastError, !gotJSONWithoutWindows {
            throw lastError
        }

        let who = fallbackEmail.map { " as \($0)" } ?? ""
        let plan = fallbackPlan.map { " (\($0))" } ?? ""
        let codexHint = triedCodexAuth && codexTokens == nil
            ? " No readable ~/.codex/auth.json (from `codex login`) was found."
            : ""
        throw QuotaError.noUsableQuota(
            "Signed in\(who)\(plan), but ChatGPT did not publish remaining/used percentages on wham/usage (or conversation_limit). CodexBar uses GET /backend-api/wham/usage with tokens from `codex login` (~/.codex/auth.json). QuotaBar does not invent numbers.\(codexHint)"
        )
    }

    struct SessionInfo: Equatable {
        var accessToken: String
        var email: String?
        var planName: String?
    }

    /// Validates a chatgpt.com cookie against `/api/auth/session`.
    /// Success means a real `accessToken` — an empty `{}` session is not enough.
    static func sessionInfo(cookie: String) async throws -> SessionInfo {
        guard let normalized = normalizeCookie(cookie) else {
            throw QuotaError.notSignedIn("ChatGPT session cookie is empty.")
        }
        let identity = try await fetchSession(cookie: normalized)
        return SessionInfo(
            accessToken: identity.accessToken,
            email: identity.email,
            planName: identity.planName
        )
    }

    static func hasSessionToken(in cookies: [HTTPCookie]) -> Bool {
        cookies.contains { cookie in
            let name = cookie.name.lowercased()
            return name.contains("session-token") || name == "oai-sc"
        }
    }

    /// Cookie header for chatgpt.com / openai.com hosts (session token plus the rest).
    static func cookieHeader(from cookies: [HTTPCookie]) -> String? {
        let relevant = cookies.filter(isChatGPTRelatedCookie)
        guard !relevant.isEmpty else { return nil }
        let header = HTTPCookie.requestHeaderFields(with: relevant)["Cookie"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (header?.isEmpty == false) ? header : nil
    }

    static func isChatGPTRelatedCookie(_ cookie: HTTPCookie) -> Bool {
        let raw = cookie.domain.lowercased()
        let host = raw.hasPrefix(".") ? String(raw.dropFirst()) : raw
        return host == "chatgpt.com"
            || host.hasSuffix(".chatgpt.com")
            || host == "chat.openai.com"
            || host == "openai.com"
            || host.hasSuffix(".openai.com")
    }

    static func isLikelyAuthURL(_ url: URL?) -> Bool {
        guard let url, let host = url.host?.lowercased() else { return true }
        if host.contains("accounts.google.com")
            || host.contains("login.microsoftonline.com")
            || host.contains("appleid.apple.com")
            || host.contains("login.live.com") {
            return true
        }
        let path = url.path.lowercased()
        if host.contains("auth.openai.com") {
            return !path.contains("callback") && !path.contains("success")
        }
        if host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") || host == "chat.openai.com" {
            return path.contains("/auth")
                || path.contains("/login")
                || path.contains("/log-in")
                || path.contains("/sign-in")
                || path.contains("/signup")
                || path.contains("/sign-up")
        }
        return true
    }

    static func parsePastedOrOfficial(_ raw: String, fetchedAt: Date, source: SnapshotSource) throws -> UsageSnapshot {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw QuotaError.schema("ChatGPT JSON is empty.")
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw QuotaError.schema("ChatGPT JSON is not UTF-8.")
        }
        let object = try JSONWalk.object(from: data)
        if let snapshot = parseUsageObject(object, planName: nil, fetchedAt: fetchedAt, source: source) {
            return snapshot
        }
        throw QuotaError.noUsableQuota(
            "Could not find remaining/used percentages in the pasted ChatGPT JSON. CodexBar uses GET /backend-api/wham/usage with ~/.codex/auth.json from `codex login`; QuotaBar does not invent numbers."
        )
    }

    // MARK: - Auth

    private struct Identity {
        var accessToken: String
        var email: String?
        var planName: String?
        var accountId: String?
    }

    private static func fetchSession(cookie: String) async throws -> Identity {
        let url = URL(string: "https://chatgpt.com/api/auth/session")!
        let (data, response) = try await HTTPClient.get(
            url: url,
            headers: [
                "Cookie": cookie,
                "Referer": "https://chatgpt.com/",
                "Origin": "https://chatgpt.com"
            ]
        )
        try HTTPClient.requireOK(response, data: data, host: "chatgpt.com")
        let object = try JSONWalk.object(from: data)
        guard let accessToken = object["accessToken"] as? String, !accessToken.isEmpty else {
            throw QuotaError.unauthorized("chatgpt.com session cookie did not return an access token.")
        }
        let user = object["user"] as? [String: Any]
        let account = object["account"] as? [String: Any]
        let plan = JSONWalk.string(account ?? [:], keys: ["planType", "plan", "plan_type"])
            ?? JSONWalk.string(user ?? [:], keys: ["planType", "plan"])
        return Identity(
            accessToken: accessToken,
            email: user?["email"] as? String,
            planName: plan.map(humanPlanName),
            accountId: accountId(fromSession: object, accessToken: accessToken)
        )
    }

    private static func fetchPlanName(accessToken: String, accountId: String?) async throws -> String {
        let url = URL(string: "https://chatgpt.com/backend-api/accounts/check/v4-2023-04-27")!
        let (data, response) = try await HTTPClient.get(
            url: url,
            headers: bearerHeaders(accessToken, cookie: nil, accountId: accountId)
        )
        try HTTPClient.requireOK(response, data: data, host: "chatgpt.com")
        let object = try JSONWalk.object(from: data)
        let entitlements = JSONWalk.dictionaries(in: object)
            .compactMap { $0.object["entitlement"] as? [String: Any] ?? ($0.key == "entitlement" ? $0.object : nil) }
        if let entitlement = entitlements.first {
            if let plan = entitlement["subscription_plan"] as? String {
                return humanPlanName(plan)
            }
        }
        throw QuotaError.schema("No plan on accounts/check.")
    }

    private static func bearerHeaders(_ accessToken: String, cookie: String?, accountId: String?) -> [String: String] {
        var headers = [
            "Authorization": "Bearer \(accessToken)",
            "Origin": "https://chatgpt.com",
            "Referer": "https://chatgpt.com/"
        ]
        if let cookie { headers["Cookie"] = cookie }
        if let accountId = nonEmpty(accountId) {
            headers["ChatGPT-Account-Id"] = accountId
        }
        return headers
    }

    static func normalizeCookie(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("cookie:") {
            return normalizeCookie(String(trimmed.dropFirst(7)))
        }
        if trimmed.contains("=") {
            return trimmed
        }
        return "\(sessionCookieName)=\(trimmed)"
    }

    private static func humanPlanName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "chatgptplusplan", "plus": return "Plus"
        case "chatgptproplan", "pro": return "Pro"
        case "chatgptteamplan", "team": return "Team"
        case "chatgptenterpriseplan", "enterprise": return "Enterprise"
        case "free", "chatgptfreeplan": return "Free"
        default: return TitleCase.words(
            raw.replacingOccurrences(of: "chatgpt", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "plan", with: "", options: .caseInsensitive)
        )
        }
    }

    // MARK: - Live usage

    /// Returns a snapshot when `wham/usage` includes usable rate-limit windows.
    /// 401/403 throw. 200/404 without percentages return `nil` so callers can fall back.
    private static func requestWhamUsage(
        accessToken: String,
        cookie: String?,
        accountId: String?,
        email: String?,
        planName: String?,
        now: Date
    ) async throws -> UsageSnapshot? {
        var lastError: Error?
        var sawJSONWithoutWindows = false

        for urlString in whamURLs {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, response) = try await HTTPClient.get(
                    url: url,
                    headers: bearerHeaders(accessToken, cookie: cookie, accountId: accountId)
                )
                if response.statusCode == 401 || response.statusCode == 403 {
                    throw QuotaError.unauthorized(
                        "\(url.host ?? "chatgpt.com") rejected the session (\(response.statusCode))."
                    )
                }
                if response.statusCode == 404 { continue }
                try HTTPClient.requireOK(response, data: data, host: url.host ?? "chatgpt.com")
                let object = try JSONWalk.object(from: data)
                if let snapshot = parseWhamUsage(
                    object,
                    email: email,
                    fallbackPlan: planName,
                    fetchedAt: now,
                    source: .live
                ) {
                    return snapshot
                }
                sawJSONWithoutWindows = true
            } catch let error as QuotaError where error.isAuthFailure {
                throw error
            } catch {
                lastError = error
            }
        }

        if sawJSONWithoutWindows {
            return nil
        }
        if let lastError {
            throw lastError
        }
        return nil
    }

    private static func fetchConversationLimit(
        accessToken: String,
        cookie: String?,
        accountId: String?,
        email: String?,
        planName: String?,
        now: Date
    ) async throws -> UsageSnapshot? {
        var lastError: Error?
        var sawJSONWithoutWindows = false

        for urlString in conversationLimitURLs {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, response) = try await HTTPClient.get(
                    url: url,
                    headers: bearerHeaders(accessToken, cookie: cookie, accountId: accountId)
                )
                if response.statusCode == 404 { continue }
                try HTTPClient.requireOK(response, data: data, host: url.host ?? "chatgpt.com")
                let object = try JSONWalk.object(from: data)
                if var snapshot = parseUsageObject(object, planName: planName, fetchedAt: now, source: .live) {
                    snapshot.accountEmail = email
                    return snapshot
                }
                sawJSONWithoutWindows = true
                lastError = QuotaError.noUsableQuota(
                    "ChatGPT \(url.lastPathComponent) returned JSON without remaining/used percentages."
                )
            } catch {
                lastError = error
            }
        }

        if let lastError = lastError as? QuotaError, lastError.isAuthFailure {
            throw lastError
        }
        if sawJSONWithoutWindows {
            return nil
        }
        if let lastError {
            throw lastError
        }
        return nil
    }

    // MARK: - Parsing

    private struct CandidateWindow {
        var title: String
        var remaining: Double
        var used: Double
        var resetAt: Date?
        var windowSeconds: TimeInterval?
        var extra: String?
    }

    static func parseUsageObject(
        _ raw: [String: Any],
        planName: String?,
        fetchedAt: Date,
        source: SnapshotSource
    ) -> UsageSnapshot? {
        if let snapshot = parseWhamUsage(
            raw,
            email: nil,
            fallbackPlan: planName,
            fetchedAt: fetchedAt,
            source: source
        ) {
            return snapshot
        }

        if let snapshot = parseCanonical(raw, fallbackPlan: planName, fetchedAt: fetchedAt, source: source) {
            return snapshot
        }

        var candidates: [CandidateWindow] = []
        for entry in JSONWalk.dictionaries(in: raw) {
            if let candidate = candidate(from: entry.object, key: entry.key) {
                candidates.append(candidate)
            }
        }

        candidates = dedupe(candidates)
        guard !candidates.isEmpty else { return nil }

        let classified = candidates.map { candidate -> QuotaWindowKind.Classified in
            let duration = candidate.windowSeconds
            let kind: QuotaWindowKind
            if let duration = duration, let fromDuration = QuotaWindowKind.fromDuration(duration) {
                kind = fromDuration
            } else if candidate.title == "Session" {
                kind = .session
            } else if candidate.title == "Weekly" {
                kind = .weekly
            } else if candidate.title == "Monthly" {
                kind = .monthly
            } else {
                kind = QuotaWindowKind.classify(
                    durationSeconds: duration,
                    resetAt: candidate.resetAt,
                    now: fetchedAt
                ) ?? .weekly
            }
            var window = toWindow(candidate, fallbackTitle: kind.title)
            window.title = kind.title
            return QuotaWindowKind.Classified(kind: kind, window: window, durationSeconds: duration)
        }
        let slots = QuotaWindowKind.assignChatGPTSlots(classified)
        let plan = planName
            ?? JSONWalk.string(raw, keys: ["plan", "planName", "plan_type", "planType"])
            .map(humanPlanName)

        return UsageSnapshot(
            provider: .chatgpt,
            planName: plan,
            fetchedAt: fetchedAt,
            session: slots.session,
            weekly: slots.longer,
            source: source,
            extraFooter: nil
        )
    }

    /// CodexBar-shaped `wham/usage`. Classify each window by duration
    /// (`limit_window_seconds` / `window_seconds` / `windowDurationMins`),
    /// not by primary → Session / secondary → Weekly. Requires `used_percent` —
    /// never invents a bar from `credits` alone.
    private static func parseWhamUsage(
        _ raw: [String: Any],
        email: String?,
        fallbackPlan: String?,
        fetchedAt: Date,
        source: SnapshotSource
    ) -> UsageSnapshot? {
        let rateLimit: [String: Any]
        if let nested = raw["rate_limit"] as? [String: Any] {
            rateLimit = nested
        } else if raw["primary_window"] != nil || raw["secondary_window"] != nil
                    || raw["primaryWindow"] != nil || raw["secondaryWindow"] != nil {
            rateLimit = raw
        } else {
            return nil
        }

        var objects: [[String: Any]] = []
        for key in ["primary_window", "primaryWindow", "secondary_window", "secondaryWindow"] {
            if let object = rateLimit[key] as? [String: Any] {
                objects.append(object)
            }
        }
        objects = dedupeRateLimitObjects(objects)

        let classified = objects.compactMap { object in
            classifiedRateLimitWindow(object, now: fetchedAt)
        }
        guard !classified.isEmpty else { return nil }

        let slots = QuotaWindowKind.assignChatGPTSlots(classified)
        let plan = JSONWalk.string(raw, keys: ["plan_type", "planType", "plan"])
            .map(humanPlanName)
            ?? fallbackPlan

        var snapshot = UsageSnapshot(
            provider: .chatgpt,
            planName: plan,
            fetchedAt: fetchedAt,
            session: slots.session,
            weekly: slots.longer,
            source: source,
            extraFooter: creditsFooter(from: raw)
        )
        snapshot.accountEmail = email
        return snapshot
    }

    private static func classifiedRateLimitWindow(
        _ object: [String: Any],
        now: Date
    ) -> QuotaWindowKind.Classified? {
        guard let used = JSONNumber.double(from: object["used_percent"] ?? object["usedPercent"]) else {
            return nil
        }
        let reset = TimeFormatting.parseDate(
            object["reset_at"]
                ?? object["resetAt"]
                ?? object["resets_at"]
                ?? object["resetsAt"]
        )
        let duration = QuotaWindowKind.durationSeconds(from: object)
        let kind = QuotaWindowKind.classify(
            durationSeconds: duration,
            resetAt: reset,
            now: now
        ) ?? .weekly
        let window = UsageWindow(
            title: kind.title,
            remainingPercent: Percent.remaining(used: used),
            usedPercent: Percent.clamp(used),
            resetAt: reset
        )
        return QuotaWindowKind.Classified(kind: kind, window: window, durationSeconds: duration)
    }

    private static func dedupeRateLimitObjects(_ objects: [[String: Any]]) -> [[String: Any]] {
        var seen: [String] = []
        var result: [[String: Any]] = []
        for object in objects {
            let used = JSONNumber.double(from: object["used_percent"] ?? object["usedPercent"]) ?? -1
            let reset = TimeFormatting.parseDate(
                object["reset_at"] ?? object["resetAt"] ?? object["resets_at"] ?? object["resetsAt"]
            )?.timeIntervalSince1970 ?? -1
            let duration = QuotaWindowKind.durationSeconds(from: object) ?? -1
            let key = "\(used)-\(reset)-\(duration)"
            if seen.contains(key) { continue }
            seen.append(key)
            result.append(object)
        }
        return result
    }

    private static func titleForWindowSeconds(_ seconds: Double, fallback: String) -> String {
        QuotaWindowKind.fromDuration(seconds)?.title ?? fallback
    }

    /// Footer only — never a percent bar.
    private static func creditsFooter(from object: [String: Any]) -> String? {
        guard let credits = object["credits"] as? [String: Any] else { return nil }
        if let unlimited = credits["unlimited"] as? Bool, unlimited {
            return "Credits unlimited"
        }
        if let flag = JSONNumber.double(from: credits["unlimited"]), flag != 0 {
            return "Credits unlimited"
        }
        if let balance = JSONNumber.double(from: credits["balance"]) {
            if abs(balance - balance.rounded()) < 0.05 {
                return "Credits \(Int(balance.rounded()))"
            }
            return "Credits \(balance)"
        }
        return nil
    }

    private static func parseCanonical(
        _ raw: [String: Any],
        fallbackPlan: String?,
        fetchedAt: Date,
        source: SnapshotSource
    ) -> UsageSnapshot? {
        let sessionObj = raw["session"] as? [String: Any]
        let weeklyObj = raw["weekly"] as? [String: Any]
        guard sessionObj != nil || weeklyObj != nil else { return nil }

        func window(from object: [String: Any]?, title: String) -> UsageWindow? {
            guard let object else { return nil }
            let remaining = JSONNumber.double(from: object["remainingPercent"] ?? object["remaining"])
            let used = JSONNumber.double(from: object["usedPercent"] ?? object["used"])
            guard let pair = Percent.fromRemainingUsed(remaining: remaining, used: used, limit: JSONNumber.double(from: object["limit"])) else {
                return nil
            }
            return UsageWindow(
                title: (object["label"] as? String) ?? title,
                remainingPercent: pair.remaining,
                usedPercent: pair.used,
                resetAt: TimeFormatting.parseDate(object["resetAt"] ?? object["reset_at"] ?? object["resetAfter"])
            )
        }

        let session = window(from: sessionObj, title: "Session")
        let weekly = window(from: weeklyObj, title: "Weekly")
        guard session != nil || weekly != nil else { return nil }
        let plan = fallbackPlan
            ?? JSONWalk.string(raw, keys: ["plan", "planName", "plan_type"])
            .map(humanPlanName)
        return UsageSnapshot(
            provider: .chatgpt,
            planName: plan,
            fetchedAt: fetchedAt,
            session: session,
            weekly: weekly,
            source: source,
            extraFooter: nil
        )
    }

    private static func candidate(from object: [String: Any], key: String?) -> CandidateWindow? {
        let explicitRemaining = firstNumber(object, keys: ["remaining_percent", "remainingPercent", "percent_left", "percentLeft"])
        let explicitUsed = firstNumber(object, keys: ["used_percent", "usedPercent", "percent_used", "percentUsed", "percentage"])
        let remainingCount = JSONNumber.double(from: object["remaining"])
        let usedCount = JSONNumber.double(from: object["used"])
        let limit = firstNumber(object, keys: ["limit", "max", "message_cap", "cap"])

        let pair: (remaining: Double, used: Double)
        if let explicitRemaining {
            pair = (Percent.clamp(explicitRemaining), Percent.remaining(used: explicitRemaining))
        } else if let explicitUsed {
            pair = (Percent.remaining(used: explicitUsed), Percent.clamp(explicitUsed))
        } else if let computed = Percent.fromRemainingUsed(remaining: remainingCount, used: usedCount, limit: limit), limit != nil {
            pair = computed
        } else {
            return nil
        }

        var reset = TimeFormatting.parseDate(
            object["resetAt"]
                ?? object["reset_at"]
                ?? object["reset_after"]
                ?? object["resetAfter"]
                ?? object["resets_after"]
        )
        if reset == nil, let seconds = JSONNumber.double(from: object["reset_after_seconds"] ?? object["resetAfterSeconds"]), seconds > 0, seconds < 1_000_000 {
            reset = Date().addingTimeInterval(seconds)
        }
        let windowSeconds = QuotaWindowKind.durationSeconds(from: object)

        let title = inferTitle(key: key, object: object, windowSeconds: windowSeconds)
        return CandidateWindow(
            title: title,
            remaining: pair.remaining,
            used: pair.used,
            resetAt: reset,
            windowSeconds: windowSeconds,
            extra: nil
        )
    }

    private static func firstNumber(_ object: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = JSONNumber.double(from: object[key]) { return value }
        }
        return nil
    }

    private static func inferTitle(key: String?, object: [String: Any], windowSeconds: TimeInterval?) -> String {
        let blob = ([key] + [
            object["feature_name"] as? String,
            object["model"] as? String,
            object["name"] as? String,
            object["label"] as? String,
            object["type"] as? String
        ]).compactMap { $0 }.joined(separator: " ").lowercased()

        if blob.contains("month") { return "Monthly" }
        if blob.contains("week") || blob.contains("thinking") { return "Weekly" }
        if blob.contains("session") || blob.contains("5") || blob.contains("3-hour") || blob.contains("3h") {
            return "Session"
        }
        if let seconds = windowSeconds {
            return titleForWindowSeconds(seconds, fallback: key.flatMap { $0.isEmpty ? nil : TitleCase.words($0) } ?? "Usage")
        }
        return key.flatMap { $0.isEmpty ? nil : TitleCase.words($0) } ?? "Usage"
    }

    private static func dedupe(_ candidates: [CandidateWindow]) -> [CandidateWindow] {
        var seen: [String] = []
        var result: [CandidateWindow] = []
        for candidate in candidates {
            let key = "\(Int(candidate.remaining.rounded()))-\(Int(candidate.used.rounded()))-\(candidate.windowSeconds ?? -1)-\(candidate.resetAt?.timeIntervalSince1970 ?? -1)"
            if seen.contains(key) { continue }
            seen.append(key)
            result.append(candidate)
        }
        return result
    }

    private static func toWindow(_ candidate: CandidateWindow, fallbackTitle: String) -> UsageWindow {
        UsageWindow(
            title: candidate.title.isEmpty ? fallbackTitle : candidate.title,
            remainingPercent: candidate.remaining,
            usedPercent: candidate.used,
            resetAt: candidate.resetAt,
            extra: candidate.extra
        )
    }

    // MARK: - Identity helpers

    private static func accountId(fromSession object: [String: Any], accessToken: String) -> String? {
        if let account = object["account"] as? [String: Any],
           let id = JSONWalk.string(account, keys: ["id", "account_id", "accountId", "chatgpt_account_id"]) {
            return id
        }
        if let id = JSONWalk.string(object, keys: ["account_id", "accountId", "chatgpt_account_id"]) {
            return id
        }
        if let user = object["user"] as? [String: Any],
           let id = JSONWalk.string(user, keys: ["account_id", "accountId", "chatgpt_account_id"]) {
            return id
        }
        if let payload = JWT.payload(accessToken) {
            return accountId(fromJWT: payload)
        }
        return nil
    }

    private static func accountId(fromJWT payload: [String: Any]) -> String? {
        if let id = JSONWalk.string(payload, keys: ["chatgpt_account_id", "account_id", "chatgptAccountId"]) {
            return id
        }
        if let auth = payload["https://api.openai.com/auth"] as? [String: Any] {
            return JSONWalk.string(auth, keys: ["chatgpt_account_id", "account_id"])
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Read-only Codex CLI OAuth file. Codex CLI owns refresh and writes;
    /// QuotaBar never updates this file and never starts a Codex OAuth dance.
    private enum CodexCLIAuth {
        struct Tokens {
            var accessToken: String
            var accountId: String?
            var email: String?
            var planName: String?
        }

        static func fileURL() -> URL {
            let env = ProcessInfo.processInfo.environment["CODEX_HOME"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !env.isEmpty {
                let expanded = (env as NSString).expandingTildeInPath
                return URL(fileURLWithPath: expanded, isDirectory: true)
                    .appendingPathComponent("auth.json")
            }
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("auth.json")
        }

        static func read() -> Tokens? {
            let url = fileURL()
            let path = url.path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: path),
                  let data = try? Data(contentsOf: url),
                  let object = try? JSONWalk.object(from: data)
            else { return nil }

            let tokens = object["tokens"] as? [String: Any] ?? [:]
            guard let access = ChatGPTClient.nonEmpty(tokens["access_token"] as? String) else { return nil }

            var accountId = ChatGPTClient.nonEmpty(tokens["account_id"] as? String)
            var email: String?
            if let idToken = ChatGPTClient.nonEmpty(tokens["id_token"] as? String),
               let payload = JWT.payload(idToken) {
                email = JSONWalk.string(payload, keys: ["email", "email_address", "preferred_username"])
                if accountId == nil {
                    accountId = ChatGPTClient.accountId(fromJWT: payload)
                }
            }
            if accountId == nil, let payload = JWT.payload(access) {
                accountId = ChatGPTClient.accountId(fromJWT: payload)
            }
            return Tokens(accessToken: access, accountId: accountId, email: email, planName: nil)
        }
    }
}
