import Foundation

enum OpenCodeGoClient {
    static let usageURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    static func fetch(apiKey: String?, now: Date = Date()) async throws -> UsageSnapshot {
        guard let token = resolveToken(explicit: apiKey) else {
            throw QuotaError.notSignedIn("Paste an OpenCode Go API key in Settings.")
        }

        let (data, response) = try await HTTPClient.get(
            url: usageURL,
            headers: [
                "Authorization": "Bearer \(token)"
            ],
            followRedirects: false
        )
        if response.statusCode == 401 {
            throw QuotaError.unauthorized("OpenCode rejected this API key (401).")
        }
        if response.statusCode == 403 {
            throw noSubscriptionError(data: data)
        }
        try HTTPClient.requireOK(response, data: data, host: usageURL.host ?? "opencode.ai")
        let object = try JSONWalk.object(from: data)
        return try parse(object, fetchedAt: now)
    }

    static func resolveToken(explicit: String?) -> String? {
        if let explicit {
            let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        for name in ["OPENCODE_GO_API_KEY", "OPENCODE_API_KEY"] {
            if let value = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func parse(_ raw: [String: Any], fetchedAt: Date = Date()) throws -> UsageSnapshot {
        let usage: [String: Any]
        if let nested = raw["usage"] as? [String: Any] {
            usage = nested
        } else {
            usage = raw
        }

        let session = window(from: usage["rolling"] ?? usage["session"], title: "Session")
        let weekly = window(from: usage["weekly"], title: "Weekly")
        let monthly = window(from: usage["monthly"], title: "Monthly")
        guard session != nil || weekly != nil || monthly != nil else {
            throw QuotaError.noUsableQuota(
                "OpenCode Go usage had no rolling/weekly/monthly percentages. QuotaBar does not invent numbers."
            )
        }

        let plan = JSONWalk.string(raw, keys: ["plan", "planName", "plan_name"])
            ?? JSONWalk.string(usage, keys: ["plan", "planName"])
            ?? "Go"
        var snapshot = UsageSnapshot(
            provider: .opencodeGo,
            planName: plan,
            fetchedAt: fetchedAt,
            session: session,
            weekly: weekly,
            monthly: monthly,
            source: .live,
            extraFooter: nil
        )
        snapshot.accountEmail = JSONWalk.string(raw, keys: ["email", "accountEmail"])
            ?? JSONWalk.string(usage, keys: ["email", "accountEmail"])
        return snapshot
    }

    /// `percent` is used 0–100, same as the OpenCode dashboard “X% used”.
    static func window(from raw: Any?, title: String) -> UsageWindow? {
        guard let object = raw as? [String: Any] else { return nil }
        guard let used = JSONNumber.double(from: object["percent"] ?? object["usedPercent"] ?? object["used_percent"]) else {
            return nil
        }
        let status = (object["status"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let status, status != "ok", status != "rate-limited" {
            return nil
        }
        let extra = status == "rate-limited" ? "Rate limited" : nil
        return UsageWindow(
            title: title,
            remainingPercent: Percent.remaining(used: used),
            usedPercent: Percent.clamp(used),
            resetAt: TimeFormatting.parseDate(
                object["resetsAt"] ?? object["resets_at"] ?? object["resetAt"] ?? object["reset_at"]
            ),
            extra: extra
        )
    }

    private static func noSubscriptionError(data: Data) -> QuotaError {
        if let object = try? JSONWalk.object(from: data) {
            let name = JSONWalk.string(object, keys: ["name", "error", "code", "type"]) ?? ""
            if name.localizedCaseInsensitiveContains("entitlement") {
                return QuotaError.noUsableQuota("This API key has no OpenCode Go subscription.")
            }
        }
        return QuotaError.noUsableQuota("This API key has no OpenCode Go subscription.")
    }
}
