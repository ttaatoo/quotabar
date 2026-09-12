import Foundation

/// Consumer Grok / SuperGrok usage via the Grok CLI-proxy REST path (CodexBar order).
/// Does not call the xAI Management API, `grok agent stdio`, Chrome cookies, or gRPC-web WKE.
enum GrokClient {
    static let billingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    static let settingsURL = URL(string: "https://cli-chat-proxy.grok.com/v1/settings")!

    static func fetch(
        pastedToken: String?,
        useAmbientFile: Bool = true,
        allowEnvironment: Bool = true,
        grokHomePath: String? = nil,
        now: Date = Date()
    ) async throws -> UsageSnapshot {
        let credentials = try GrokAuth.resolve(
            pasted: pastedToken,
            useAmbientFile: useAmbientFile,
            allowEnvironment: allowEnvironment,
            grokHomePath: grokHomePath
        )
        let headers = proxyHeaders(token: credentials.accessToken)

        let (data, response) = try await HTTPClient.get(url: billingURL, headers: headers)
        try HTTPClient.requireOK(response, data: data, host: billingURL.host ?? "cli-chat-proxy.grok.com")

        let object = try JSONWalk.object(from: data)
        let extras = await fetchSettingsExtras(token: credentials.accessToken)
        let plan = extras.plan ?? credentials.planFallback
        var snapshot = try parse(
            object,
            email: credentials.email ?? extras.email,
            planFallback: plan,
            fetchedAt: now
        )
        if snapshot.accountEmail == nil {
            snapshot.accountEmail = extras.email ?? AccountIdentity.fromToken(credentials.accessToken)
        }
        return snapshot
    }

    /// `GET /v1/settings` is optional enrichment. A 2s timeout or any failure must not block usage.
    static func fetchSubscriptionTier(token: String) async -> String? {
        await fetchSettingsExtras(token: token).plan
    }

    static func fetchSettingsExtras(token: String) async -> (plan: String?, email: String?) {
        do {
            let (data, response) = try await HTTPClient.get(
                url: settingsURL,
                headers: proxyHeaders(token: token),
                timeout: 2
            )
            guard (200...299).contains(response.statusCode) else { return (nil, nil) }
            let object = try JSONWalk.object(from: data)
            let plan = GrokAuth.displayPlanName(
                JSONWalk.string(object, keys: ["subscription_tier_display", "subscriptionTierDisplay"])
            )
            return (plan, AccountIdentity.fromJSON(object))
        } catch {
            return (nil, nil)
        }
    }

    static func parse(
        _ raw: [String: Any],
        email: String?,
        planFallback: String?,
        fetchedAt: Date = Date()
    ) throws -> UsageSnapshot {
        let config: [String: Any]
        if let nested = raw["config"] as? [String: Any] {
            config = nested
        } else {
            config = raw
        }

        let resetAt = periodEnd(from: config) ?? periodEnd(from: raw)
        let usedPercent = try usedPercent(from: config, resetAt: resetAt)

        let title: String
        if let kind = QuotaWindowKind.fromReset(resetAt, now: fetchedAt) {
            title = kind.title
        } else {
            title = "Credits"
        }

        let window = UsageWindow(
            title: title,
            remainingPercent: Percent.remaining(used: usedPercent),
            usedPercent: Percent.clamp(usedPercent),
            resetAt: resetAt
        )

        let session: UsageWindow?
        let weekly: UsageWindow?
        if let kind = QuotaWindowKind.fromReset(resetAt, now: fetchedAt), kind == .session {
            session = window
            weekly = nil
        } else {
            session = nil
            weekly = window
        }

        let plan = GrokAuth.displayPlanName(
            JSONWalk.string(raw, keys: ["subscription_tier_display", "subscriptionTierDisplay"])
                ?? JSONWalk.string(config, keys: ["subscriptionTier", "subscription_tier"])
        ) ?? GrokAuth.displayPlanName(planFallback)

        var snapshot = UsageSnapshot(
            provider: .grok,
            planName: plan,
            fetchedAt: fetchedAt,
            session: session,
            weekly: weekly,
            source: .live,
            extraFooter: nil
        )
        snapshot.accountEmail = email
            ?? AccountIdentity.fromJSON(raw)
            ?? JSONWalk.string(raw, keys: ["email", "accountEmail"])
        return snapshot
    }

    /// CodexBar rule: `creditUsagePercent`, else on-demand ratio, else 0% when a current
    /// period is parseable. Never invent a bar from credits-alone with no period.
    static func usedPercent(from config: [String: Any], resetAt: Date?) throws -> Double {
        if let percent = JSONNumber.double(from: config["creditUsagePercent"]), percent.isFinite {
            return Percent.clamp(percent)
        }

        let used = amountVal(config["onDemandUsed"])
        let cap = amountVal(config["onDemandCap"])
        if let used, let cap, cap > 0 {
            return Percent.clamp(used / cap * 100)
        }

        if resetAt != nil {
            return 0
        }

        throw QuotaError.schema(
            "Grok billing had no creditUsagePercent, on-demand ratio, or current period — not inventing a bar."
        )
    }

    private static func periodEnd(from object: [String: Any]) -> Date? {
        if let current = object["currentPeriod"] as? [String: Any] {
            if let end = TimeFormatting.parseDate(current["end"]) {
                return end
            }
        }
        return TimeFormatting.parseDate(object["billingPeriodEnd"] ?? object["billing_period_end"])
    }

    private static func amountVal(_ raw: Any?) -> Double? {
        if let object = raw as? [String: Any] {
            return JSONNumber.double(from: object["val"])
        }
        return JSONNumber.double(from: raw)
    }

    private static func proxyHeaders(token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "x-xai-token-auth": "xai-grok-cli"
        ]
    }
}
