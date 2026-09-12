import Foundation

enum FixtureLoader {
    static func load(
        _ provider: ProviderKind,
        now: Date = Date(),
        variant: Int = 0,
        emailOverride: String? = nil
    ) throws -> UsageSnapshot {
        guard let url = Bundle.main.url(forResource: provider.rawValue, withExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.main.url(forResource: provider.rawValue, withExtension: "json")
        else {
            throw QuotaError.schema("Missing \(provider.rawValue).json fixture in the app bundle.")
        }
        let data = try Data(contentsOf: url)
        let object = try JSONWalk.object(from: data)
        var snapshot: UsageSnapshot
        switch provider {
        case .cursor:
            let email = JSONWalk.string(object, keys: ["email", "accountEmail"])
            snapshot = try CursorClient.parse(object, fetchedAt: now, email: email)
        case .chatgpt:
            guard let parsed = ChatGPTClient.parseUsageObject(object, planName: nil, fetchedAt: now, source: .fixture) else {
                throw QuotaError.schema("ChatGPT fixture had no usable windows.")
            }
            snapshot = varyChatGPT(parsed, variant: variant)
        case .glm:
            snapshot = try GLMClient.parse(object, fetchedAt: now)
        case .grok:
            let email = JSONWalk.string(object, keys: ["email", "accountEmail"])
            let plan = JSONWalk.string(object, keys: ["subscription_tier_display", "plan", "planName"])
            snapshot = try GrokClient.parse(object, email: email, planFallback: plan, fetchedAt: now)
        case .opencodeGo:
            snapshot = try OpenCodeGoClient.parse(object, fetchedAt: now)
            snapshot = varyOpenCodeGo(snapshot, variant: variant)
        }
        snapshot.source = .fixture
        snapshot.fetchedAt = now
        if let email = emailOverride ?? snapshot.accountEmail ?? JSONWalk.string(object, keys: ["email", "accountEmail"]) {
            snapshot.accountEmail = email
        }
        if var session = snapshot.session {
            session.resetAt = now.addingTimeInterval((2 * 3600) + (49 * 60))
            snapshot.session = session
        }
        if var weekly = snapshot.weekly {
            weekly.resetAt = now.addingTimeInterval((4 * 86_400) + (12 * 3600))
            snapshot.weekly = weekly
        }
        if var monthly = snapshot.monthly {
            monthly.resetAt = now.addingTimeInterval((18 * 86_400) + (6 * 3600))
            snapshot.monthly = monthly
        }
        return snapshot
    }

    /// Distinct preview cards so multi-account ChatGPT is screenshottable.
    /// Variant 0 keeps the bundled Plus session+weekly; later variants drop
    /// Session (Plus / Prolite / Free often publish only Weekly).
    private static func varyChatGPT(_ snapshot: UsageSnapshot, variant: Int) -> UsageSnapshot {
        guard variant > 0 else { return snapshot }
        var snap = snapshot
        let remainingChoices = [12.0, 67.0, 34.0]
        let remaining = remainingChoices[(variant - 1) % remainingChoices.count]
        let weekly = UsageWindow(
            title: "Weekly",
            remainingPercent: remaining,
            usedPercent: 100 - remaining,
            resetAt: snapshot.weekly?.resetAt ?? snapshot.session?.resetAt
        )
        snap.session = nil
        snap.weekly = weekly
        switch variant % 3 {
        case 1: snap.planName = "Prolite"
        case 2: snap.planName = "Free"
        default: snap.planName = snapshot.planName ?? "Plus"
        }
        return snap
    }

    private static func varyOpenCodeGo(_ snapshot: UsageSnapshot, variant: Int) -> UsageSnapshot {
        guard variant > 0 else { return snapshot }
        var snap = snapshot
        let usedChoices = [27.0, 64.0, 9.0]
        let used = usedChoices[(variant - 1) % usedChoices.count]
        if var weekly = snap.weekly {
            weekly.usedPercent = used
            weekly.remainingPercent = Percent.remaining(used: used)
            snap.weekly = weekly
        }
        return snap
    }
}
