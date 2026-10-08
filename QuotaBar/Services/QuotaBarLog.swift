import Foundation
#if canImport(os)
import os
#endif

enum QuotaBarLog {
#if canImport(os)
    private static let refreshLog = Logger(subsystem: "app.quotabar", category: "refresh")
    private static let configLog = Logger(subsystem: "app.quotabar", category: "config")
    private static let keychainLog = Logger(subsystem: "app.quotabar", category: "keychain")
#endif

    static func refreshInfo(_ message: String) {
        #if canImport(os)
        refreshLog.info("\(message, privacy: .public)")
        #endif
    }

    static func configError(_ message: String) {
        #if canImport(os)
        configLog.error("\(message, privacy: .public)")
        #endif
    }

    static func keychainError(_ message: String) {
        #if canImport(os)
        keychainLog.error("\(message, privacy: .public)")
        #endif
    }

    static func keychainInfo(_ message: String) {
        #if canImport(os)
        keychainLog.info("\(message, privacy: .public)")
        #endif
    }
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

    /// Diagnostics shows the classified message, never a bearer or cookie echoed by a host.
    static func redactedMessage(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("bearer ")
            || lower.contains("session-token")
            || lower.contains("refresh_token") {
            return "response omitted"
        }
        // A bare "eyJ" shows up in ordinary text. Only a dotted JWT shape is a token.
        if message.range(of: #"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#, options: .regularExpression) != nil {
            return "response omitted"
        }
        if message.count > 180 {
            return String(message.prefix(180))
        }
        return message
    }
}
