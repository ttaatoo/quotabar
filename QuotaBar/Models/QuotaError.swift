import Foundation

enum QuotaError: LocalizedError, Equatable {
    case notSignedIn(String)
    case unauthorized(String)
    case http(Int, String)
    case schema(String)
    case network(String)
    case noUsableQuota(String)

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
        }
    }

    var isAuthFailure: Bool {
        switch self {
        case .notSignedIn, .unauthorized:
            return true
        case .http(let code, _) where code == 401 || code == 403:
            return true
        default:
            return false
        }
    }
}
