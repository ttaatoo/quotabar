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
    var accountEmail: String? = nil

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

    /// ChatGPT menu bar: the Weekly (or longer) meter the account card already
    /// shows. Session-only accounts fall back to `mostConstrainedRemaining`.
    var chatGPTMenuRemaining: Double? {
        if let weekly, !weekly.unlimited {
            return weekly.remainingPercent
        }
        return mostConstrainedRemaining
    }

    var isChatGPTMenuLow: Bool {
        guard let remaining = chatGPTMenuRemaining else { return false }
        return remaining < 25
    }
}

/// ChatGPT / `wham/usage` lanes by **duration**, not primary/secondary slot.
/// Plus and Codex often put a 7-day (10080 min) window in `primary` with no 5-hour session.
enum QuotaWindowKind: String, Equatable {
    case session
    case weekly
    case monthly

    var title: String {
        switch self {
        case .session: return "Session"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    struct Classified: Equatable {
        var kind: QuotaWindowKind
        var window: UsageWindow
        var durationSeconds: TimeInterval?
    }

    /// ≤ ~12h → Session; ~3–14d (incl. 10080 min) → Weekly; ~30d (43200 min) → Monthly.
    static func fromDuration(_ seconds: TimeInterval) -> QuotaWindowKind? {
        guard seconds > 0 else { return nil }
        if seconds <= 12 * 3600 { return .session }
        if seconds >= 20 * 86_400 { return .monthly }
        if seconds >= 3 * 86_400 { return .weekly }
        return nil
    }

    /// A reset days away is Weekly (or Monthly if ~20d+), never Session.
    static func fromReset(_ resetAt: Date?, now: Date) -> QuotaWindowKind? {
        guard let resetAt else { return nil }
        let remaining = resetAt.timeIntervalSince(now)
        if remaining <= 0 { return nil }
        if remaining <= 12 * 3600 { return .session }
        if remaining >= 20 * 86_400 { return .monthly }
        if remaining >= 86_400 { return .weekly }
        return nil
    }

    static func classify(durationSeconds: TimeInterval?, resetAt: Date?, now: Date) -> QuotaWindowKind? {
        if let durationSeconds = durationSeconds, let kind = fromDuration(durationSeconds) {
            return kind
        }
        return fromReset(resetAt, now: now)
    }

    static func durationSeconds(from object: [String: Any]) -> TimeInterval? {
        let minuteKeys = [
            "windowDurationMins", "window_duration_mins",
            "window_minutes", "windowMinutes", "window_duration_minutes"
        ]
        for key in minuteKeys {
            if let mins = JSONNumber.double(from: object[key]), mins > 0 {
                return mins * 60
            }
        }
        let secondKeys = [
            "limit_window_seconds", "window_seconds",
            "windowSeconds", "limitWindowSeconds"
        ]
        for key in secondKeys {
            if let seconds = JSONNumber.double(from: object[key]), seconds > 0 {
                return seconds
            }
        }
        if let value = JSONNumber.double(from: object["message_cap_window"]), value > 0 {
            // Historical conversation_limit used minutes when the value is small.
            if value <= 24 * 60 {
                return value * 60
            }
            return value
        }
        return nil
    }

    /// Session is only returned when a real ≤12h window exists (omitted otherwise).
    /// The longer slot is Weekly, or Monthly when that is the only longer window.
    /// A lone ChatGPT window that is not a real ≤12h session is Weekly (or Monthly).
    static func assignChatGPTSlots(_ items: [Classified]) -> (session: UsageWindow?, longer: UsageWindow?) {
        if items.count == 1, let only = items.first {
            if only.kind == .session,
               let duration = only.durationSeconds,
               duration > 0,
               duration <= 12 * 3600 {
                return (only.window, nil)
            }
            var window = only.window
            if only.kind == .monthly {
                window.title = QuotaWindowKind.monthly.title
                return (nil, window)
            }
            window.title = QuotaWindowKind.weekly.title
            return (nil, window)
        }

        let session = items.first(where: { $0.kind == .session })?.window
        if let weekly = items.first(where: { $0.kind == .weekly })?.window {
            return (session, weekly)
        }
        if let monthly = items.first(where: { $0.kind == .monthly })?.window {
            return (session, monthly)
        }
        return (session, nil)
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
