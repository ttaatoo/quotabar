import Foundation

enum ChatGPTClient {
    private static let sessionCookieName = "__Secure-next-auth.session-token"

    static func fetch(cookie pasted: String?, pastedJSON: String?, now: Date = Date()) async throws -> UsageSnapshot {
        if let cookie = normalizeCookie(pasted) {
            do {
                return try await fetchLive(cookie: cookie, now: now)
            } catch let error as QuotaError where error.isAuthFailure {
                if let pastedJSON, let snapshot = try? parsePastedOrOfficial(pastedJSON, fetchedAt: now, source: .pastedJSON) {
                    return snapshot
                }
                throw error
            } catch {
                if let pastedJSON, let snapshot = try? parsePastedOrOfficial(pastedJSON, fetchedAt: now, source: .pastedJSON) {
                    return snapshot
                }
                throw error
            }
        }

        if let pastedJSON {
            return try parsePastedOrOfficial(pastedJSON, fetchedAt: now, source: .pastedJSON)
        }

        throw QuotaError.notSignedIn("Add a chatgpt.com session cookie in Settings, or paste conversation_limit JSON.")
    }

    private static func fetchLive(cookie: String, now: Date) async throws -> UsageSnapshot {
        let identity = try await fetchSession(cookie: cookie)
        var planName = identity.planName

        if planName == nil {
            planName = try? await fetchPlanName(accessToken: identity.accessToken)
        }

        let candidates = [
            "https://chatgpt.com/backend-api/conversation_limit",
            "https://chatgpt.com/public-api/conversation_limit"
        ]

        var lastError: Error?
        for urlString in candidates {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, response) = try await HTTPClient.get(
                    url: url,
                    headers: bearerHeaders(identity.accessToken, cookie: cookie)
                )
                if response.statusCode == 404 { continue }
                try HTTPClient.requireOK(response, data: data, host: "chatgpt.com")
                let object = try JSONWalk.object(from: data)
                if var snapshot = parseUsageObject(object, planName: planName, fetchedAt: now, source: .live) {
                    snapshot.accountEmail = identity.email
                    return snapshot
                }
                lastError = QuotaError.noUsableQuota("ChatGPT \(url.lastPathComponent) returned JSON without remaining/used percentages.")
            } catch {
                lastError = error
            }
        }

        if let lastError = lastError as? QuotaError, lastError.isAuthFailure {
            throw lastError
        }

        throw QuotaError.noUsableQuota(
            "Signed in\(identity.email.map { " as \($0)" } ?? "")\(planName.map { " (\($0))" } ?? ""), but ChatGPT did not publish remaining quota on conversation_limit. Paste that response JSON from DevTools in Settings. Numbers are never invented."
        )
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
        throw QuotaError.noUsableQuota("Could not find remaining/used percentages in the pasted ChatGPT JSON.")
    }

    // MARK: - Auth

    private struct Identity {
        var accessToken: String
        var email: String?
        var planName: String?
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
            planName: plan.map(humanPlanName)
        )
    }

    private static func fetchPlanName(accessToken: String) async throws -> String {
        let url = URL(string: "https://chatgpt.com/backend-api/accounts/check/v4-2023-04-27")!
        let (data, response) = try await HTTPClient.get(url: url, headers: bearerHeaders(accessToken, cookie: nil))
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

    private static func bearerHeaders(_ accessToken: String, cookie: String?) -> [String: String] {
        var headers = [
            "Authorization": "Bearer \(accessToken)",
            "Origin": "https://chatgpt.com",
            "Referer": "https://chatgpt.com/"
        ]
        if let cookie { headers["Cookie"] = cookie }
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

        let session = pickSession(from: candidates)
        let weekly = pickWeekly(from: candidates, excluding: session)
        let plan = planName
            ?? JSONWalk.string(raw, keys: ["plan", "planName", "plan_type", "planType"])
            .map(humanPlanName)

        return UsageSnapshot(
            provider: .chatgpt,
            planName: plan,
            fetchedAt: fetchedAt,
            session: session.map { toWindow($0, fallbackTitle: "Session") },
            weekly: weekly.map { toWindow($0, fallbackTitle: "Weekly") },
            source: source,
            extraFooter: nil
        )
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
        let windowSeconds = JSONNumber.double(
            from: object["limit_window_seconds"]
                ?? object["window_seconds"]
                ?? object["message_cap_window"]
        ).map { value -> TimeInterval in
            // Historical conversation_limit used minutes for message_cap_window.
            if value > 0 && value <= 24 * 60 && object["message_cap_window"] != nil {
                return value * 60
            }
            return value
        }

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

        if blob.contains("week") || blob.contains("thinking") { return "Weekly" }
        if blob.contains("session") || blob.contains("5") || blob.contains("3-hour") || blob.contains("3h") {
            return "Session"
        }
        if let seconds = windowSeconds {
            if seconds <= 12 * 3600 { return "Session" }
            if seconds >= 3 * 86_400 { return "Weekly" }
        }
        return key.flatMap { $0.isEmpty ? nil : TitleCase.words($0) } ?? "Usage"
    }

    private static func pickSession(from candidates: [CandidateWindow]) -> CandidateWindow? {
        if let named = candidates.first(where: { $0.title == "Session" }) { return named }
        let short = candidates
            .filter { ($0.windowSeconds ?? .greatestFiniteMagnitude) <= 12 * 3600 }
            .sorted { ($0.windowSeconds ?? 0) < ($1.windowSeconds ?? 0) }
        return short.first ?? candidates.min(by: { ($0.windowSeconds ?? 0) < ($1.windowSeconds ?? .greatestFiniteMagnitude) })
    }

    private static func pickWeekly(from candidates: [CandidateWindow], excluding session: CandidateWindow?) -> CandidateWindow? {
        let rest = candidates.filter { candidate in
            guard let session else { return true }
            return !(candidate.remaining == session.remaining && candidate.used == session.used && candidate.resetAt == session.resetAt)
        }
        if let named = rest.first(where: { $0.title == "Weekly" }) { return named }
        return rest.max(by: { ($0.windowSeconds ?? 0) < ($1.windowSeconds ?? 0) })
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
}
