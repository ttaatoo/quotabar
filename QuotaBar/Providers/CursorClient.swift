import Foundation

enum CursorClient {
    static func fetch(cookie pasted: String?, now: Date = Date()) async throws -> UsageSnapshot {
        let cookie = try CursorAuth.resolveCookie(pasted: pasted)
        let headers = [
            "Cookie": cookie,
            "Origin": "https://cursor.com",
            "Referer": "https://cursor.com/dashboard?tab=usage"
        ]

        let url = URL(string: "https://cursor.com/api/usage-summary")!
        let (data, response) = try await HTTPClient.get(url: url, headers: headers)
        try HTTPClient.requireOK(response, data: data, host: "cursor.com")

        let object = try JSONWalk.object(from: data)
        return try parse(object, fetchedAt: now)
    }

    static func parse(_ raw: [String: Any], fetchedAt: Date = Date()) throws -> UsageSnapshot {
        if raw["error"] as? String == "not_authenticated" {
            throw QuotaError.unauthorized("Cursor says this session is not authenticated.")
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
            return UsageSnapshot(
                provider: .cursor,
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
                source: .live,
                extraFooter: extra
            )
        }

        if let plan = individualPlan(raw) {
            return UsageSnapshot(
                provider: .cursor,
                planName: planName,
                fetchedAt: fetchedAt,
                session: cursorModelsWindow(usedPercent: plan.autoPercentUsed, resetAt: cycleEnd),
                weekly: otherModelsWindow(usedPercent: plan.apiPercentUsed, resetAt: cycleEnd),
                source: .live,
                extraFooter: extra
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
            return UsageSnapshot(
                provider: .cursor,
                planName: "\(planName) team",
                fetchedAt: fetchedAt,
                session: cursorModelsWindow(usedPercent: autoUsed, resetAt: cycleEnd),
                weekly: otherModelsWindow(usedPercent: namedUsed, resetAt: cycleEnd),
                source: .live,
                extraFooter: extra
            )
        }

        throw QuotaError.schema("Cursor usage-summary did not include plan percentages.")
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
