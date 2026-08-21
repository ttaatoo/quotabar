import Foundation

enum TimeFormatting {
    static func relativeUpdated(from date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 10 { return "Updated just now" }
        if seconds < 60 { return "Updated \(Int(seconds))s ago" }
        if seconds < 3600 { return "Updated \(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "Updated \(Int(seconds / 3600))h ago" }
        return "Updated \(Int(seconds / 86_400))d ago"
    }

    static func countdown(until date: Date, now: Date, prefix: String) -> String {
        let remaining = date.timeIntervalSince(now)
        if remaining <= 0 { return "\(prefix) reset pending" }
        return "\(prefix) reset in \(compactDuration(remaining))"
    }

    static func compactDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(max(seconds, 1))s"
    }

    static func parseDate(_ raw: Any?) -> Date? {
        if let date = raw as? Date { return date }
        if let number = JSONNumber.double(from: raw) {
            if number > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: number / 1000)
            }
            if number > 1_000_000_000 {
                return Date(timeIntervalSince1970: number)
            }
        }
        if let string = raw as? String {
            if let date = ISO8601Parser.date(from: string) { return date }
            if let number = Double(string) {
                return parseDate(number)
            }
        }
        return nil
    }
}

enum ISO8601Parser {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let basic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from string: String) -> Date? {
        if let date = fractional.date(from: string) { return date }
        if let date = basic.date(from: string) { return date }
        return nil
    }
}
