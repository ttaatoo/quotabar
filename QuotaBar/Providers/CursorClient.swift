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
            let window = UsageWindow(
                title: "Session",
                remainingPercent: 100,
                usedPercent: 0,
                resetAt: cycleEnd,
                extra: extra,
                unlimited: true
            )
            return UsageSnapshot(
                provider: .cursor,
                planName: planName,
                fetchedAt: fetchedAt,
                session: window,
                weekly: UsageWindow(
                    title: "Weekly",
                    remainingPercent: 100,
                    usedPercent: 0,
                    resetAt: cycleEnd,
                    extra: extra,
                    unlimited: true
                ),
                source: .live,
                extraFooter: extra
            )
        }

        if let plan = individualPlan(raw) {
            let sessionRemaining = Percent.remaining(used: plan.autoPercentUsed)
            let weeklyRemaining: Double
            if let used = plan.used, let limit = plan.limit, limit > 0 {
                weeklyRemaining = ((limit - used) / limit) * 100
            } else {
                weeklyRemaining = Percent.remaining(used: plan.totalPercentUsed)
            }

            return UsageSnapshot(
                provider: .cursor,
                planName: planName,
                fetchedAt: fetchedAt,
                session: UsageWindow(
                    title: "Session",
                    remainingPercent: sessionRemaining,
                    usedPercent: plan.autoPercentUsed,
                    resetAt: cycleEnd,
                    extra: extra
                ),
                weekly: UsageWindow(
                    title: "Weekly",
                    remainingPercent: weeklyRemaining,
                    usedPercent: 100 - weeklyRemaining,
                    resetAt: cycleEnd,
                    extra: extra
                ),
                source: .live,
                extraFooter: extra
            )
        }

        if let auto = raw["autoModelSelectedDisplayMessage"] as? String,
           let named = raw["namedModelSelectedDisplayMessage"] as? String,
           let autoUsed = Percent.parseMessage(auto),
           let namedUsed = Percent.parseMessage(named) {
            let weeklyUsed = max(autoUsed, namedUsed)
            return UsageSnapshot(
                provider: .cursor,
                planName: "\(planName) team",
                fetchedAt: fetchedAt,
                session: UsageWindow(
                    title: "Session",
                    remainingPercent: Percent.remaining(used: autoUsed),
                    usedPercent: autoUsed,
                    resetAt: cycleEnd,
                    extra: extra
                ),
                weekly: UsageWindow(
                    title: "Weekly",
                    remainingPercent: Percent.remaining(used: weeklyUsed),
                    usedPercent: weeklyUsed,
                    resetAt: cycleEnd,
                    extra: extra
                ),
                source: .live,
                extraFooter: extra
            )
        }

        throw QuotaError.schema("Cursor usage-summary did not include plan percentages.")
    }

    private struct PlanFields {
        var autoPercentUsed: Double
        var totalPercentUsed: Double
        var used: Double?
        var limit: Double?
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
        let total = JSONNumber.double(from: plan["totalPercentUsed"])
        if let auto, let total {
            return PlanFields(
                autoPercentUsed: auto,
                totalPercentUsed: total,
                used: JSONNumber.double(from: plan["used"]),
                limit: JSONNumber.double(from: plan["limit"])
            )
        }
        if let used = JSONNumber.double(from: plan["used"]),
           let limit = JSONNumber.double(from: plan["limit"]),
           limit > 0 {
            let percent = (used / limit) * 100
            return PlanFields(autoPercentUsed: percent, totalPercentUsed: percent, used: used, limit: limit)
        }
        return nil
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
