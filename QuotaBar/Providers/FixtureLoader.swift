import Foundation

enum FixtureLoader {
    static func load(_ provider: ProviderKind, now: Date = Date()) throws -> UsageSnapshot {
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
            snapshot = try CursorClient.parse(object, fetchedAt: now)
        case .chatgpt:
            guard let parsed = ChatGPTClient.parseUsageObject(object, planName: nil, fetchedAt: now, source: .fixture) else {
                throw QuotaError.schema("ChatGPT fixture had no usable windows.")
            }
            snapshot = parsed
        case .glm:
            snapshot = try GLMClient.parse(object, fetchedAt: now)
        }
        snapshot.source = .fixture
        snapshot.fetchedAt = now
        if var session = snapshot.session {
            session.resetAt = now.addingTimeInterval((2 * 3600) + (49 * 60))
            snapshot.session = session
        }
        if var weekly = snapshot.weekly {
            weekly.resetAt = now.addingTimeInterval((4 * 86_400) + (12 * 3600))
            snapshot.weekly = weekly
        }
        return snapshot
    }
}
