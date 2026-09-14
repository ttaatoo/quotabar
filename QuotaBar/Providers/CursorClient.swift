import Foundation

enum CursorClient {
    static func fetch(cookie pasted: String?, now: Date = Date()) async throws -> UsageSnapshot {
        let session = try CursorAuth.resolveSession(pasted: pasted)
        do {
            return try await fetchResolved(session, now: now)
        } catch {
            guard shouldAttemptRefresh(kind: session.kind, error: error) else {
                throw error
            }
            let token = try await CursorAuth.refreshAmbientAccessToken()
            return try await fetchResolved(
                CursorAuth.session(fromAccessToken: token, kind: .ambient),
                now: now
            )
        }
    }

    /// Refresh only on a real auth failure from the primary path — never WAF HTML 403.
    static func shouldAttemptRefresh(kind: CursorAuth.SessionKind, error: Error) -> Bool {
        guard kind == .ambient else { return false }
        guard let quota = error as? QuotaError else { return false }
        switch quota {
        case .unauthorized:
            return true
        default:
            return false
        }
    }

    private static func fetchResolved(
        _ session: CursorAuth.ResolvedSession,
        now: Date
    ) async throws -> UsageSnapshot {
        switch session.kind {
        case .ambient:
            guard let token = session.accessToken, !token.isEmpty else {
                throw QuotaError.notSignedIn(CursorAuth.notSignedInMessage)
            }
            return try await fetchAPI2(accessToken: token, now: now)
        case .pasted:
            do {
                return try await fetchUsageSummary(cookie: session.cookie, now: now)
            } catch {
                guard CursorHTTP.isCheckpointError(error),
                      let token = session.accessToken, !token.isEmpty
                else { throw error }
                return try await fetchAPI2(accessToken: token, now: now)
            }
        }
    }

    /// `POST GetCurrentPeriodUsage` with Bearer — avoids Vercel on cursor.com.
    private static func fetchAPI2(
        accessToken: String,
        now: Date,
        allowCheckpointRetry: Bool = true
    ) async throws -> UsageSnapshot {
        let (data, response) = try await HTTPClient.postJSON(
            url: periodUsageURL(),
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "Connect-Protocol-Version": "1"
            ],
            body: [:]
        )
        switch CursorHTTP.classify(
            status: response.statusCode,
            data: data,
            contentType: response.value(forHTTPHeaderField: "Content-Type")
        ) {
        case .unauthorized:
            throw QuotaError.unauthorized(CursorAuth.unauthenticatedMessage)
        case .checkpoint:
            if allowCheckpointRetry {
                return try await fetchAPI2(
                    accessToken: accessToken,
                    now: now,
                    allowCheckpointRetry: false
                )
            }
            throw QuotaError.network(CursorHTTP.checkpointMessage)
        case .failure:
            try HTTPClient.requireOK(response, data: data, host: "api2.cursor.sh")
        case .ok:
            break
        }

        let object = try JSONWalk.object(from: data)
        if CursorHTTP.isUnauthenticatedJSON(object) {
            throw QuotaError.unauthorized(CursorAuth.unauthenticatedMessage)
        }

        let profile = await fetchStripeProfile(accessToken: accessToken)
        let email = resolveAPI2Email(usage: object, profile: profile, accessToken: accessToken)
        let planName = planNameFromStripe(profile)
            ?? JSONWalk.string(object, keys: ["membershipType", "plan", "planType"])
        return try parsePeriodUsage(object, fetchedAt: now, email: email, planName: planName)
    }

    private static func fetchUsageSummary(cookie: String, now: Date) async throws -> UsageSnapshot {
        let headers = [
            "Cookie": cookie,
            "Origin": "https://cursor.com",
            "Referer": "https://cursor.com/dashboard?tab=usage"
        ]

        let url = URL(string: "https://cursor.com/api/usage-summary")!
        let (data, response) = try await HTTPClient.get(url: url, headers: headers)
        switch CursorHTTP.classify(
            status: response.statusCode,
            data: data,
            contentType: response.value(forHTTPHeaderField: "Content-Type")
        ) {
        case .unauthorized:
            throw QuotaError.unauthorized(CursorAuth.rejectedSessionMessage(status: response.statusCode))
        case .checkpoint:
            throw QuotaError.network(CursorHTTP.checkpointMessage)
        case .failure:
            try HTTPClient.requireOK(response, data: data, host: "cursor.com")
        case .ok:
            break
        }

        let object = try JSONWalk.object(from: data)
        if CursorHTTP.isUnauthenticatedJSON(object) {
            throw QuotaError.unauthorized(CursorAuth.unauthenticatedMessage)
        }
        let email = await resolveEmail(cookie: cookie, usageObject: object)
        return try parse(object, fetchedAt: now, email: email)
    }

    private static func fetchStripeProfile(accessToken: String) async -> [String: Any]? {
        do {
            let (data, response) = try await HTTPClient.get(
                url: stripeProfileURL(),
                headers: ["Authorization": "Bearer \(accessToken)"]
            )
            switch CursorHTTP.classify(
                status: response.statusCode,
                data: data,
                contentType: response.value(forHTTPHeaderField: "Content-Type")
            ) {
            case .ok:
                let object = try JSONWalk.object(from: data)
                if CursorHTTP.isUnauthenticatedJSON(object) { return nil }
                return object
            default:
                return nil
            }
        } catch {
            return nil
        }
    }

    static func parse(_ raw: [String: Any], fetchedAt: Date = Date(), email: String? = nil) throws -> UsageSnapshot {
        if CursorHTTP.isUnauthenticatedJSON(raw) {
            throw QuotaError.unauthorized(CursorAuth.unauthenticatedMessage)
        }

        let membership = JSONWalk.string(raw, keys: ["membershipType", "plan", "planType"]) ?? "Pro"
        let planName = TitleCase.words(membership)
        let unlimited = (raw["isUnlimited"] as? Bool) ?? false
        let cycleEnd = TimeFormatting.parseDate(raw["billingCycleEnd"])

        var extra: String?
        if let onDemand = individualOnDemand(raw) ?? teamOnDemand(raw), onDemand.enabled {
            extra = onDemand.footer
        }

        if unlimited {
            return snapshot(
                planName: planName,
                fetchedAt: fetchedAt,
                session: UsageWindow(
                    title: "Cursor Models",
                    remainingPercent: 100,
                    usedPercent: 0,
                    resetAt: cycleEnd,
                    unlimited: true
                ),
                weekly: UsageWindow(
                    title: "Other Models",
                    remainingPercent: 100,
                    usedPercent: 0,
                    resetAt: cycleEnd,
                    unlimited: true
                ),
                extraFooter: extra,
                email: email
            )
        }

        if let plan = individualPlan(raw) {
            return snapshot(
                planName: planName,
                fetchedAt: fetchedAt,
                session: cursorModelsWindow(usedPercent: plan.autoPercentUsed, resetAt: cycleEnd),
                weekly: otherModelsWindow(usedPercent: plan.apiPercentUsed, resetAt: cycleEnd),
                extraFooter: extra,
                email: email
            )
        }

        let autoUsed: Double?
        if let message = raw["autoModelSelectedDisplayMessage"] as? String {
            autoUsed = Percent.parseMessage(message)
        } else {
            autoUsed = nil
        }
        let namedUsed: Double?
        if let message = raw["namedModelSelectedDisplayMessage"] as? String {
            namedUsed = Percent.parseMessage(message)
        } else {
            namedUsed = nil
        }
        if autoUsed != nil || namedUsed != nil {
            return snapshot(
                planName: "\(planName) team",
                fetchedAt: fetchedAt,
                session: cursorModelsWindow(usedPercent: autoUsed, resetAt: cycleEnd),
                weekly: otherModelsWindow(usedPercent: namedUsed, resetAt: cycleEnd),
                extraFooter: extra,
                email: email
            )
        }

        throw QuotaError.schema("Cursor usage-summary did not include plan percentages.")
    }

    /// Maps `GetCurrentPeriodUsage` (`planUsage` + `billingCycleEnd`) into the
    /// same Cursor Models / Other Models snapshot as usage-summary.
    static func parsePeriodUsage(
        _ raw: [String: Any],
        fetchedAt: Date = Date(),
        email: String? = nil,
        planName: String? = nil
    ) throws -> UsageSnapshot {
        if CursorHTTP.isUnauthenticatedJSON(raw) {
            throw QuotaError.unauthorized(CursorAuth.unauthenticatedMessage)
        }

        let membership = planName
            ?? JSONWalk.string(raw, keys: ["membershipType", "plan", "planType"])
            ?? "Pro"
        let displayPlan = TitleCase.words(membership)
        let cycleEnd = TimeFormatting.parseDate(raw["billingCycleEnd"])
        let extra = onDemandFooter(fromPeriod: raw)

        if let plan = raw["planUsage"] as? [String: Any] {
            let auto = JSONNumber.double(from: plan["autoPercentUsed"])
            let api = JSONNumber.double(from: plan["apiPercentUsed"])
            if auto != nil || api != nil {
                return snapshot(
                    planName: displayPlan,
                    fetchedAt: fetchedAt,
                    session: cursorModelsWindow(usedPercent: auto, resetAt: cycleEnd),
                    weekly: otherModelsWindow(usedPercent: api, resetAt: cycleEnd),
                    extraFooter: extra,
                    email: email
                )
            }

            let autoMessage = (raw["autoModelSelectedDisplayMessage"] as? String)
                .flatMap(Percent.parseMessage)
            let namedMessage = (raw["namedModelSelectedDisplayMessage"] as? String)
                .flatMap(Percent.parseMessage)
            if autoMessage != nil || namedMessage != nil {
                return snapshot(
                    planName: displayPlan,
                    fetchedAt: fetchedAt,
                    session: cursorModelsWindow(usedPercent: autoMessage, resetAt: cycleEnd),
                    weekly: otherModelsWindow(usedPercent: namedMessage, resetAt: cycleEnd),
                    extraFooter: extra,
                    email: email
                )
            }

            if let used = totalPercentUsed(from: plan) {
                return snapshot(
                    planName: displayPlan,
                    fetchedAt: fetchedAt,
                    session: cursorModelsWindow(usedPercent: used, resetAt: cycleEnd),
                    weekly: nil,
                    extraFooter: extra,
                    email: email
                )
            }
        }

        let autoMessage = (raw["autoModelSelectedDisplayMessage"] as? String)
            .flatMap(Percent.parseMessage)
        let namedMessage = (raw["namedModelSelectedDisplayMessage"] as? String)
            .flatMap(Percent.parseMessage)
        if autoMessage != nil || namedMessage != nil {
            return snapshot(
                planName: displayPlan,
                fetchedAt: fetchedAt,
                session: cursorModelsWindow(usedPercent: autoMessage, resetAt: cycleEnd),
                weekly: otherModelsWindow(usedPercent: namedMessage, resetAt: cycleEnd),
                extraFooter: extra,
                email: email
            )
        }

        throw QuotaError.schema("Cursor period usage did not include plan percentages.")
    }

    private static func totalPercentUsed(from plan: [String: Any]) -> Double? {
        if let total = JSONNumber.double(from: plan["totalPercentUsed"]) {
            return total
        }
        let included = JSONNumber.double(from: plan["includedSpend"])
        let limit = JSONNumber.double(from: plan["limit"])
        if let included, let limit, limit > 0 {
            return (included / limit) * 100
        }
        return nil
    }

    private static func onDemandFooter(fromPeriod raw: [String: Any]) -> String? {
        if let existing = individualOnDemand(raw) ?? teamOnDemand(raw), existing.enabled {
            return existing.footer
        }
        guard let spend = raw["spendLimitUsage"] as? [String: Any] else { return nil }
        let individualLimit = JSONNumber.double(from: spend["individualLimit"]) ?? 0
        let pooledLimit = JSONNumber.double(from: spend["pooledLimit"]) ?? 0
        guard individualLimit > 0 || pooledLimit > 0 else { return nil }
        let used = JSONNumber.double(from: spend["individualUsed"])
            ?? JSONNumber.double(from: spend["pooledUsed"])
            ?? JSONNumber.double(from: spend["totalSpend"])
        return OnDemandFields(enabled: true, used: used).footer
    }

    private static func snapshot(
        planName: String,
        fetchedAt: Date,
        session: UsageWindow?,
        weekly: UsageWindow?,
        extraFooter: String?,
        email: String?
    ) -> UsageSnapshot {
        var value = UsageSnapshot(
            provider: .cursor,
            planName: planName,
            fetchedAt: fetchedAt,
            session: session,
            weekly: weekly,
            source: .live,
            extraFooter: extraFooter
        )
        value.accountEmail = email
        return value
    }

    /// Prefer a real email from usage-summary, then `/api/auth/me`, then the session JWT.
    /// Never invent an address when those sources omit one.
    private static func resolveEmail(cookie: String, usageObject: [String: Any]) async -> String? {
        if let email = emailField(in: usageObject) {
            return email
        }
        if let email = await fetchAuthMeEmail(cookie: cookie) {
            return email
        }
        return CursorAuth.emailFromSessionCookie(cookie)
    }

    private static func resolveAPI2Email(
        usage: [String: Any],
        profile: [String: Any]?,
        accessToken: String
    ) -> String? {
        if let profile, let email = emailField(in: profile) {
            return email
        }
        if let email = emailField(in: usage) {
            return email
        }
        if let email = AccountIdentity.fromToken(accessToken), email.contains("@") {
            return email
        }
        return CursorAuth.readLocalTokens().cachedEmail
    }

    private static func planNameFromStripe(_ object: [String: Any]?) -> String? {
        guard let object else { return nil }
        guard let raw = JSONWalk.string(object, keys: [
            "membershipType", "individualMembershipType", "plan", "planType"
        ]) else { return nil }
        return TitleCase.words(raw)
    }

    private static func emailField(in object: [String: Any]) -> String? {
        if let email = CodexCLIAuth.email(from: object) {
            return email
        }
        return nil
    }

    private static func fetchAuthMeEmail(cookie: String) async -> String? {
        guard let url = URL(string: "https://cursor.com/api/auth/me") else { return nil }
        do {
            let (data, response) = try await HTTPClient.get(
                url: url,
                headers: [
                    "Cookie": cookie,
                    "Origin": "https://cursor.com",
                    "Referer": "https://cursor.com/dashboard?tab=usage"
                ]
            )
            switch CursorHTTP.classify(
                status: response.statusCode,
                data: data,
                contentType: response.value(forHTTPHeaderField: "Content-Type")
            ) {
            case .ok:
                break
            default:
                return nil
            }
            let object = try JSONWalk.object(from: data)
            return CodexCLIAuth.email(from: object)
        } catch {
            return nil
        }
    }

    private static func periodUsageURL() -> URL {
        let override = ProcessInfo.processInfo.environment["CURSOR_API2_USAGE_URL_OVERRIDE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !override.isEmpty, let url = URL(string: override) {
            return url
        }
        return URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    }

    private static func stripeProfileURL() -> URL {
        let override = ProcessInfo.processInfo.environment["CURSOR_API2_PROFILE_URL_OVERRIDE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !override.isEmpty, let url = URL(string: override) {
            return url
        }
        return URL(string: "https://api2.cursor.sh/auth/full_stripe_profile")!
    }

    private static func cursorModelsWindow(usedPercent: Double?, resetAt: Date?) -> UsageWindow? {
        guard let usedPercent else { return nil }
        return UsageWindow(
            title: "Cursor Models",
            remainingPercent: Percent.remaining(used: usedPercent),
            usedPercent: Percent.clamp(usedPercent),
            resetAt: resetAt
        )
    }

    private static func otherModelsWindow(usedPercent: Double?, resetAt: Date?) -> UsageWindow? {
        guard let usedPercent else { return nil }
        return UsageWindow(
            title: "Other Models",
            remainingPercent: Percent.remaining(used: usedPercent),
            usedPercent: Percent.clamp(usedPercent),
            resetAt: resetAt
        )
    }

    private struct PlanFields {
        var autoPercentUsed: Double?
        var apiPercentUsed: Double?
    }

    private struct OnDemandFields {
        var enabled: Bool
        var used: Double?
        var footer: String {
            guard enabled else { return "" }
            if let used {
                if used >= 50 {
                    let dollars = used / 100
                    return String(format: "On-demand $%.2f", dollars)
                }
                return "On-demand \(Int(used.rounded()))"
            }
            return "On-demand on"
        }
    }

    private static func individualPlan(_ raw: [String: Any]) -> PlanFields? {
        guard let individual = raw["individualUsage"] as? [String: Any],
              let plan = individual["plan"] as? [String: Any]
        else { return nil }

        let auto = JSONNumber.double(from: plan["autoPercentUsed"])
        let api = JSONNumber.double(from: plan["apiPercentUsed"])
        if auto == nil && api == nil { return nil }
        return PlanFields(autoPercentUsed: auto, apiPercentUsed: api)
    }

    private static func individualOnDemand(_ raw: [String: Any]) -> OnDemandFields? {
        guard let individual = raw["individualUsage"] as? [String: Any],
              let onDemand = individual["onDemand"] as? [String: Any]
        else { return nil }
        return OnDemandFields(
            enabled: (onDemand["enabled"] as? Bool) ?? false,
            used: JSONNumber.double(from: onDemand["used"])
        )
    }

    private static func teamOnDemand(_ raw: [String: Any]) -> OnDemandFields? {
        guard let team = raw["teamUsage"] as? [String: Any],
              let onDemand = team["onDemand"] as? [String: Any]
        else { return nil }
        return OnDemandFields(
            enabled: (onDemand["enabled"] as? Bool) ?? false,
            used: JSONNumber.double(from: onDemand["used"])
        )
    }
}

/// Distinguishes Vercel bot-challenge 403 HTML from a real Cursor auth failure.
enum CursorHTTP {
    static let checkpointMessage =
        "Cursor usage is temporarily blocked by a security checkpoint. Try Refresh again."

    enum Kind: Equatable {
        case ok
        case unauthorized
        case checkpoint
        case failure
    }

    static func classify(status: Int, data: Data, contentType: String?) -> Kind {
        if isCheckpoint(status: status, data: data, contentType: contentType) {
            return .checkpoint
        }
        if isUnauthenticated(status: status, data: data, contentType: contentType) {
            return .unauthorized
        }
        if (200...299).contains(status) {
            return .ok
        }
        return .failure
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
            "token expired"
        ]
        return markers.contains { haystack.contains($0) }
    }

    static func isCheckpointError(_ error: Error) -> Bool {
        guard let quota = error as? QuotaError, case .network(let message) = quota else {
            return false
        }
        return message.lowercased().contains("security checkpoint")
    }

    private static func looksLikeJSON(_ data: Data) -> Bool {
        guard let text = String(data: data.prefix(256), encoding: .utf8) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first == "{" || trimmed.first == "["
    }

    private static func looksLikeHTML(_ data: Data) -> Bool {
        guard let text = String(data: data.prefix(256), encoding: .utf8) else { return false }
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html")
    }
}
