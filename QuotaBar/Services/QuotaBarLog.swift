import Foundation
import os

enum QuotaBarLog {
    static let subsystem = "app.quotabar"
    static let refresh = Logger(subsystem: subsystem, category: "refresh")
    static let config = Logger(subsystem: subsystem, category: "config")
    static let keychain = Logger(subsystem: subsystem, category: "keychain")
}

struct FetchAttempt: Equatable, Identifiable, Sendable {
    var id: String
    var provider: ProviderKind
    var accountLabel: String
    var finishedAt: Date
    var kind: String
    var message: String
    var durationMs: Int
    var preservedStale: Bool

    var summary: String {
        let stale = preservedStale ? " · kept meters" : ""
        return "\(provider.title) · \(accountLabel): \(kind)\(stale)"
    }
}
