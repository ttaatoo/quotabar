import Foundation

enum QuotaError: LocalizedError, Equatable, Sendable {
    case notSignedIn(String)
    case unauthorized(String)
    case http(Int, String)
    case schema(String)
    case network(String)
    case noUsableQuota(String)
    /// Overlapped refresh or URLSession cancellation. Not a timeout and not a user-facing failure.
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notSignedIn(let message),
             .unauthorized(let message),
             .schema(let message),
             .network(let message),
             .noUsableQuota(let message):
            return message
        case .http(let code, let message):
            return "HTTP \(code): \(message)"
        case .cancelled:
            return "Cancelled."
        }
    }

    var isAuthFailure: Bool {
        switch self {
        case .notSignedIn, .unauthorized:
            return true
        case .http(let code, _) where code == 401:
            return true
        default:
            return false
        }
    }

    var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }

    /// Keep last meters only for transport / checkpoint failures — never auth, schema, HTTP, or cancellation.
    var shouldPreservePriorSnapshot: Bool {
        if case .network = self { return true }
        return false
    }
}
