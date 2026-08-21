import Foundation

enum SnapshotSource: String, Equatable {
    case live
    case fixture
    case pastedJSON
}

struct UsageWindow: Equatable {
    var title: String
    var remainingPercent: Double
    var usedPercent: Double
    var resetAt: Date?
    var extra: String?
    var unlimited: Bool

    init(
        title: String,
        remainingPercent: Double,
        usedPercent: Double? = nil,
        resetAt: Date? = nil,
        extra: String? = nil,
        unlimited: Bool = false
    ) {
        self.title = title
        self.remainingPercent = remainingPercent
        self.usedPercent = usedPercent ?? max(0, 100 - remainingPercent)
        self.resetAt = resetAt
        self.extra = extra
        self.unlimited = unlimited
    }

    func displayedPercent(mode: DisplayMode) -> Double {
        if unlimited { return mode == .remaining ? 100 : 0 }
        switch mode {
        case .remaining: return remainingPercent
        case .used: return usedPercent
        }
    }

    func isLow(mode: DisplayMode, threshold: Double = 25) -> Bool {
        if unlimited { return false }
        return remainingPercent < threshold
    }
}

struct UsageSnapshot: Equatable {
    var provider: ProviderKind
    var planName: String?
    var fetchedAt: Date
    var session: UsageWindow?
    var weekly: UsageWindow?
    var source: SnapshotSource
    var extraFooter: String?

    var windows: [UsageWindow] {
        [session, weekly].compactMap { $0 }
    }

    var mostConstrainedRemaining: Double? {
        let values = windows.filter { !$0.unlimited }.map(\.remainingPercent)
        return values.min()
    }

    var isLow: Bool {
        guard let remaining = mostConstrainedRemaining else { return false }
        return remaining < 25
    }
}

enum ProviderLoadState: Equatable {
    case idle
    case loading
    case ready(UsageSnapshot)
    case signedOut(String)
    case failure(String)

    var snapshot: UsageSnapshot? {
        if case .ready(let snap) = self { return snap }
        return nil
    }

    var isSignedOut: Bool {
        if case .signedOut = self { return true }
        return false
    }
}
