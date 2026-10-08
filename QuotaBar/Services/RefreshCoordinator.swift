import Foundation

/// Per-key refresh generations so a stale in-flight job cannot publish.
final class RefreshCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var clock = 0
    private var generations: [String: Int] = [:]
    private var inFlight: Set<String> = []

    func begin(_ key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        clock += 1
        generations[key] = clock
        inFlight.insert(key)
        return clock
    }

    func finish(_ key: String, generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        if generations[key] == generation {
            inFlight.remove(key)
        }
        pruneIdleKeysLocked()
    }

    /// Drop finished keys once the map is large. Generations are process-wide and
    /// never reused, so a late callback cannot match a new `begin`.
    private func pruneIdleKeysLocked() {
        guard generations.count > 64 else { return }
        for key in generations.keys where !inFlight.contains(key) {
            generations.removeValue(forKey: key)
        }
    }

    var inFlightKeys: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return inFlight
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

    enum PollObservation: Equatable {
        case success
        case transportFailure
        case ignored
    }

    /// Credentialed transport failures back off. A credentialed success resets.
    /// Signed-out, disabled, auth, and unconfigured rows are `.ignored` and do not
    /// raise the interval. No credentialed success or transport failure clears any
    /// penalty so a normal install does not drift to 30 minutes.
    static func nextPollFailureCount(current: Int, observations: [PollObservation]) -> Int {
        if observations.contains(.success) { return 0 }
        if observations.contains(.transportFailure) {
            return min(max(current, 0) + 1, 5)
        }
        return 0
    }

    static func observation(hasCredentials: Bool, state: ProviderLoadState) -> PollObservation {
        guard hasCredentials else { return .ignored }
        switch state {
        case .ready:
            return .success
        case .stale:
            return .transportFailure
        case .failure(let message):
            return isTransportFailureMessage(message) ? .transportFailure : .ignored
        case .signedOut, .idle, .loading:
            return .ignored
        }
    }

    static func isTransportFailureMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        if lower.contains("timed out") { return true }
        if lower.contains("security checkpoint") { return true }
        if lower.contains("offline") { return true }
        if lower.contains("network connection") { return true }
        if lower.contains("internet connection") { return true }
        if lower.contains("could not connect") { return true }
        if lower.contains("hostname could not be found") { return true }
        if lower.contains("not connected to the internet") { return true }
        return false
    }

    /// Saved accounts that are all disabled must not be replaced by a fake signed-out card.
    static func showsSyntheticSignedOutCard(savedAccountCount: Int, visibleAccountCount: Int) -> Bool {
        visibleAccountCount == 0 && savedAccountCount == 0
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
