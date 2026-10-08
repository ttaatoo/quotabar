import Foundation

/// Per-key refresh generations so a stale in-flight job cannot publish.
final class RefreshCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var generations: [String: Int] = [:]
    private var inFlight: Set<String> = []

    func begin(_ key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let next = (generations[key] ?? 0) + 1
        generations[key] = next
        inFlight.insert(key)
        return next
    }

    func finish(_ key: String, generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        if generations[key] == generation {
            inFlight.remove(key)
        }
    }

    func isCurrent(_ key: String, generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generations[key] == generation
    }

    var isRefreshing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !inFlight.isEmpty
    }

    static func key(_ provider: ProviderKind, accountID: UUID? = nil) -> String {
        if let accountID {
            return "\(provider.rawValue):\(accountID.uuidString)"
        }
        return provider.rawValue
    }

    static func needsOpenRefresh(
        _ state: ProviderLoadState,
        now: Date = Date(),
        force: Bool,
        freshWindow: TimeInterval = 30
    ) -> Bool {
        if force { return true }
        if case .ready(let snapshot) = state {
            return now.timeIntervalSince(snapshot.fetchedAt) > freshWindow
        }
        return true
    }

    /// Exponential backoff from the configured interval, capped at 30 minutes.
    static func pollDelay(base: TimeInterval, consecutiveFailures: Int) -> TimeInterval {
        let safeBase = max(base, 15)
        let capped = min(max(consecutiveFailures, 0), 5)
        return min(safeBase * pow(2, Double(capped)), 30 * 60)
    }

    /// Advance from the last scheduled tick and skip missed ticks.
    static func nextScheduledAt(previous: Date, interval: TimeInterval, now: Date) -> Date {
        var next = previous.addingTimeInterval(max(interval, 1))
        while next <= now {
            next = next.addingTimeInterval(max(interval, 1))
        }
        return next
    }
}
