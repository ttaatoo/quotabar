import Foundation

enum GLMClient {
    static func fetch(apiKey: String?, region: GLMRegion, now: Date = Date()) async throws -> UsageSnapshot {
        guard let token = resolveToken(explicit: apiKey) else {
            throw QuotaError.notSignedIn("Add a z.ai / BigModel API key in Settings, ~/.config/quotabar/config.json, or Z_AI_API_KEY.")
        }

        let url = region.host.appendingPathComponent("api/monitor/usage/quota/limit")
        let (data, response) = try await HTTPClient.get(
            url: url,
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/json"
            ]
        )
        try HTTPClient.requireOK(response, data: data, host: region.host.host ?? "z.ai")
        let object = try JSONWalk.object(from: data)
        return try parse(object, fetchedAt: now)
    }

    static func resolveToken(explicit: String?) -> String? {
        if let explicit, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicit.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let key = KeychainStore.get(.glmAPIKey), !key.isEmpty { return key }
        if let key = ConfigStore.readLegacyGLMKey(), !key.isEmpty { return key }
        for name in ["Z_AI_API_KEY", "GLM_API_KEY", "BIGMODEL_API_KEY"] {
            if let value = ProcessInfo.processInfo.environment[name], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func parse(_ raw: [String: Any], fetchedAt: Date = Date()) throws -> UsageSnapshot {
        if let success = raw["success"] as? Bool, success == false {
            let message = (raw["msg"] as? String) ?? "GLM quota request failed."
            throw QuotaError.schema(message)
        }
        if let code = JSONNumber.int(from: raw["code"]), code != 200, raw["data"] == nil {
            throw QuotaError.http(code, (raw["msg"] as? String) ?? "GLM error")
        }

        let data = (raw["data"] as? [String: Any]) ?? raw
        let plan = JSONWalk.string(data, keys: ["planName", "plan", "plan_type", "packageName", "level"])
            .map(TitleCase.words)

        let limits = (data["limits"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let tokenLimits = limits.filter { ($0["type"] as? String) == "TOKENS_LIMIT" }

        var windows: [(seconds: TimeInterval, window: UsageWindow)] = []
        for limit in tokenLimits {
            guard let parsed = parseTokenLimit(limit) else { continue }
            windows.append(parsed)
        }

        windows.sort { $0.seconds < $1.seconds }
        guard !windows.isEmpty else {
            throw QuotaError.noUsableQuota("GLM quota response had no TOKENS_LIMIT windows.")
        }

        let session = windows.first.map {
            var value = $0.window
            value.title = "Session"
            return value
        }
        let weekly: UsageWindow? = {
            if windows.count >= 2 {
                var value = windows.last!.window
                value.title = "Weekly"
                return value
            }
            if windows[0].seconds >= 3 * 86_400 {
                var value = windows[0].window
                value.title = "Weekly"
                return value
            }
            return nil
        }()

        let extra = mcpExtra(from: limits)

        return UsageSnapshot(
            provider: .glm,
            planName: plan,
            fetchedAt: fetchedAt,
            session: session,
            weekly: weekly,
            source: .live,
            extraFooter: extra
        )
    }

    private static func parseTokenLimit(_ limit: [String: Any]) -> (TimeInterval, UsageWindow)? {
        let unit = JSONNumber.int(from: limit["unit"]) ?? 0
        let number = JSONNumber.int(from: limit["number"]) ?? 0
        let seconds = windowSeconds(unit: unit, number: number)

        let usedPercent = JSONNumber.double(from: limit["percentage"])
        let remainingCount = JSONNumber.double(from: limit["remaining"])
        let usedCount = JSONNumber.double(from: limit["currentValue"])
        let cap = JSONNumber.double(from: limit["usage"])

        let pair: (remaining: Double, used: Double)
        if let usedPercent {
            pair = (Percent.remaining(used: usedPercent), usedPercent)
        } else if let computed = Percent.fromRemainingUsed(remaining: remainingCount, used: usedCount, limit: cap) {
            pair = computed
        } else {
            return nil
        }

        let reset = TimeFormatting.parseDate(limit["nextResetTime"])
        let window = UsageWindow(
            title: seconds <= 12 * 3600 ? "Session" : "Weekly",
            remainingPercent: pair.remaining,
            usedPercent: pair.used,
            resetAt: reset
        )
        return (seconds, window)
    }

    /// unit 3 = hours, unit 6 = weeks when number is small else days, unit 5 = months.
    static func windowSeconds(unit: Int, number: Int) -> TimeInterval {
        let n = Double(max(number, 0))
        switch unit {
        case 1: return n
        case 2: return n * 60
        case 3: return n * 3600
        case 4: return n * 86_400
        case 5: return n * 30 * 86_400
        case 6:
            return n <= 4 ? n * 7 * 86_400 : n * 86_400
        default:
            return n * 3600
        }
    }

    private static func mcpExtra(from limits: [[String: Any]]) -> String? {
        guard let time = limits.first(where: { ($0["type"] as? String) == "TIME_LIMIT" }) else { return nil }
        let remaining = JSONNumber.double(from: time["remaining"])
        let used = JSONNumber.double(from: time["currentValue"])
        let cap = JSONNumber.double(from: time["usage"])
        if let remaining, let cap {
            return "MCP \(Int(remaining.rounded()))/\(Int(cap.rounded()))"
        }
        if let used, let cap {
            return "MCP \(Int(used.rounded()))/\(Int(cap.rounded())) used"
        }
        if let percent = JSONNumber.double(from: time["percentage"]) {
            return String(format: "MCP %.0f%% used", percent)
        }
        return nil
    }
}
