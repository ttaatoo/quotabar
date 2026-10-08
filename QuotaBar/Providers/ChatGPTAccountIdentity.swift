import Foundation

/// ChatGPT card identity and session matching.
///
/// Two ChatGPT logins are the same session only when they share a Codex home
/// or the same access token / cookie. A matching or missing email is not proof.
enum ChatGPTAccountIdentity {
    enum Recovery: Equatable {
        case retryRefresh
        case relogin

        var buttonTitle: String {
            switch self {
            case .retryRefresh: return "Retry"
            case .relogin: return "Re-login"
            }
        }

        /// Expired cookie / Codex sessions cannot be recovered by re-reading auth.json.
        static func action(for state: ProviderLoadState) -> Recovery {
            switch state {
            case .failure(let message), .signedOut(let message), .stale(_, let message):
                return isExpiredSessionMessage(message) ? .relogin : .retryRefresh
            default:
                return .retryRefresh
            }
        }

        static func isExpiredSessionMessage(_ message: String) -> Bool {
            let lower = message.lowercased()
            if lower.contains("session cookie") { return true }
            if lower.contains("codex login expired") { return true }
            if lower.contains("token expired") { return true }
            if lower.contains("session expired") { return true }
            return false
        }
    }

    /// Both emails must be present and equal. A missing email is not a match.
    static func identitiesMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let left = CodexCLIAuth.usableEmail(lhs),
              let right = CodexCLIAuth.usableEmail(rhs)
        else { return false }
        return left.caseInsensitiveCompare(right) == .orderedSame
    }

    /// Fetch validation: only fail when both emails exist and disagree.
    /// A missing email is not enough to reject a scoped home / cookie fetch.
    static func emailsCompatible(_ found: String?, _ expected: String?) -> Bool {
        guard let left = CodexCLIAuth.usableEmail(found),
              let right = CodexCLIAuth.usableEmail(expected)
        else { return true }
        return left.caseInsensitiveCompare(right) == .orderedSame
    }

    static func representsHome(_ account: ChatGPTAccount, homePath: String) -> Bool {
        if CodexCLIAuth.homesMatch(account.codexHomePath, homePath) {
            return true
        }
        if CodexCLIAuth.isAmbientHomePath(homePath)
            && (account.usesAmbientCodexHome || CodexCLIAuth.isAmbientHomePath(account.codexHomePath)) {
            return true
        }
        return false
    }

    static func matchExisting(
        accounts: [ChatGPTAccount],
        homePath: String?,
        accessToken: String?,
        excluding id: UUID? = nil
    ) -> ChatGPTAccount? {
        if let homePath, !homePath.isEmpty,
           let byHome = accounts.first(where: {
               $0.id != id && representsHome($0, homePath: homePath)
           }) {
            return byHome
        }
        guard let incomingToken = accessToken, !incomingToken.isEmpty else { return nil }
        return accounts.first { account in
            account.id != id && Self.accessToken(for: account) == incomingToken
        }
    }

    static func accessToken(for account: ChatGPTAccount) -> String? {
        guard let home = CodexCLIAuth.homeURL(path: account.codexHomePath) else {
            if account.usesAmbientCodexHome {
                return CodexCLIAuth.read()?.accessToken
            }
            return nil
        }
        return CodexCLIAuth.read(home: home)?.accessToken
    }

    @discardableResult
    static func upsertFromHome(
        accounts: inout [ChatGPTAccount],
        homePath: String,
        email: String?,
        ambient: Bool,
        accessToken: String?,
        nextLabel: String
    ) -> UUID {
        let standardizedHome = CodexCLIAuth.homeURL(path: homePath)?.path(percentEncoded: false) ?? homePath
        let incoming = CodexCLIAuth.usableEmail(email)

        if let existing = matchExisting(
            accounts: accounts,
            homePath: standardizedHome,
            accessToken: accessToken
        ), let index = accounts.firstIndex(where: { $0.id == existing.id }) {
            let sameHome = representsHome(accounts[index], homePath: standardizedHome)
            let sameToken = accessToken.map { self.accessToken(for: accounts[index]) == $0 } ?? false
            if sameToken, !sameHome {
                // Point this row at the incoming home, but keep the previous
                // directory. A copied auth.json can share an access token
                // while the old managed home still holds the refresh token.
                accounts[index].codexHomePath = standardizedHome
                accounts[index].usesAmbientCodexHome = ambient
            } else if sameHome {
                accounts[index].usesAmbientCodexHome = ambient
                if accounts[index].codexHomePath == nil {
                    accounts[index].codexHomePath = standardizedHome
                }
            }
            assignIdentity(incoming, to: existing.id, accounts: &accounts)
            return existing.id
        }

        let emailTaken = incoming.map { candidate in
            accounts.contains { $0.email?.caseInsensitiveCompare(candidate) == .orderedSame }
        } ?? false
        let label = (!emailTaken ? incoming : nil) ?? nextLabel
        let id = UUID()
        accounts.append(
            ChatGPTAccount(
                id: id,
                label: label,
                enabled: true,
                email: nil,
                codexHomePath: standardizedHome,
                usesAmbientCodexHome: ambient
            )
        )
        assignIdentity(incoming, to: id, accounts: &accounts)
        return id
    }

    /// Persist a real email only when no other row already uses it.
    @discardableResult
    static func assignIdentity(
        _ identity: String?,
        to id: UUID,
        accounts: inout [ChatGPTAccount]
    ) -> Bool {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return false }
        let preferred = CodexCLIAuth.usableEmail(identity)
        let currentEmail = CodexCLIAuth.usableEmail(accounts[index].email)
        let colliding: Bool = {
            guard let preferred else { return false }
            return accounts.contains {
                $0.id != id
                    && $0.email?.caseInsensitiveCompare(preferred) == .orderedSame
            }
        }()
        let next: String?
        if let preferred, !colliding {
            next = preferred
        } else if colliding {
            if let currentEmail, currentEmail.caseInsensitiveCompare(preferred ?? "") != .orderedSame {
                next = currentEmail
            } else {
                next = nil
            }
        } else {
            next = currentEmail
        }
        guard accounts[index].email != next else { return false }
        accounts[index].email = next
        return true
    }
}
