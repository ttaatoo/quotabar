import Foundation

/// Grok card identity and session matching.
///
/// Two Grok logins are the same session only when they share a home path or
/// the same access token. A matching / missing email is not proof — `grok`
/// can carry a previous profile onto a new token, and `/v1/settings` used to
/// be walked for any nested `email`.
enum GrokAccountIdentity {
    struct Resolved: Equatable {
        var display: String?
        var uniqueFallback: String?

        var cardIdentity: String? { display ?? uniqueFallback }
    }

    struct CardInput: Equatable {
        var id: UUID
        var storedEmail: String?
        var snapshotEmail: String?
        var label: String
        var uniqueFallback: String?
    }

    static func jwtEmail(_ token: String) -> String? {
        guard let payload = JWT.payload(token) else { return nil }
        return CodexCLIAuth.email(from: payload)
    }

    /// Top-level / `user` / `account` email only. Does not walk every nested
    /// dictionary — billing and settings payloads can contain a shared address.
    static func emailFromUserObject(_ object: [String: Any]) -> String? {
        CodexCLIAuth.email(from: object)
    }

    static func resolve(
        credentials: GrokAuth.Credentials,
        settingsEmail: String? = nil
    ) -> Resolved {
        let display = jwtEmail(credentials.accessToken)
            ?? CodexCLIAuth.usableEmail(credentials.email)
            ?? CodexCLIAuth.usableEmail(settingsEmail)
        let unique = uniqueFallback(
            token: credentials.accessToken,
            userId: credentials.userId,
            homePath: nil
        )
        return Resolved(display: display, uniqueFallback: unique)
    }

    static func uniqueFallback(token: String?, userId: String?, homePath: String?) -> String? {
        if let token, let sub = JWT.trailingSubject(token),
           let short = AccountIdentity.shortenID(sub) {
            return short
        }
        if let userId, let short = AccountIdentity.shortenID(userId) {
            return short
        }
        if let homePath {
            let name = URL(fileURLWithPath: homePath).lastPathComponent
            if name.count >= 8 {
                return AccountIdentity.shortenID(name)
            }
        }
        return nil
    }

    static func uniqueFallback(account: GrokAccount, pastedToken: String? = nil) -> String? {
        let creds = GrokAuth.credentials(for: account)
        return uniqueFallback(
            token: creds?.accessToken ?? GrokAuth.normalizedOAuthToken(pastedToken),
            userId: creds?.userId,
            homePath: account.grokHomePath
        )
    }

    static func representsHome(_ account: GrokAccount, homePath: String) -> Bool {
        if GrokAuth.homesMatch(account.grokHomePath, homePath) {
            return true
        }
        if GrokAuth.isAmbientHomePath(homePath)
            && (account.usesAmbientAuthFile || GrokAuth.isAmbientHomePath(account.grokHomePath)) {
            return true
        }
        return false
    }

    /// Same session: same Grok home, or the same access token in that home.
    static func matchExisting(
        accounts: [GrokAccount],
        homePath: String,
        accessToken: String?
    ) -> GrokAccount? {
        if let byHome = accounts.first(where: { representsHome($0, homePath: homePath) }) {
            return byHome
        }
        guard let accessToken, !accessToken.isEmpty else { return nil }
        return accounts.first { account in
            GrokAuth.accessToken(for: account) == accessToken
        }
    }

    @discardableResult
    static func upsertFromHome(
        accounts: inout [GrokAccount],
        homePath: String,
        email: String?,
        ambient: Bool,
        accessToken: String?,
        userId: String? = nil,
        nextLabel: String
    ) -> UUID {
        let standardizedHome = GrokAuth.homeURL(path: homePath)?.path(percentEncoded: false) ?? homePath
        let incoming = AccountIdentity.usableHandle(email)
        let fallback = uniqueFallback(token: accessToken, userId: userId, homePath: standardizedHome)

        if let existing = matchExisting(
            accounts: accounts,
            homePath: standardizedHome,
            accessToken: accessToken
        ), let index = accounts.firstIndex(where: { $0.id == existing.id }) {
            let sameHome = representsHome(accounts[index], homePath: standardizedHome)
            let sameToken = accessToken.map { GrokAuth.accessToken(for: accounts[index]) == $0 } ?? false
            if sameToken, !sameHome {
                let previousHome = accounts[index].grokHomePath
                accounts[index].grokHomePath = standardizedHome
                accounts[index].usesAmbientAuthFile = ambient
                if !GrokAuth.homesMatch(previousHome, standardizedHome) {
                    GrokAuth.removeManagedHomeIfSafe(previousHome)
                }
            } else if sameHome {
                accounts[index].usesAmbientAuthFile = ambient
                if accounts[index].grokHomePath == nil {
                    accounts[index].grokHomePath = standardizedHome
                }
            }
            assignIdentity(incoming, fallback: fallback, to: existing.id, accounts: &accounts)
            return existing.id
        }

        let emailTaken = incoming.map { candidate in
            accounts.contains { $0.email?.caseInsensitiveCompare(candidate) == .orderedSame }
        } ?? false
        let label = (!emailTaken ? CodexCLIAuth.usableEmail(incoming) : nil) ?? nextLabel
        let id = UUID()
        accounts.append(
            GrokAccount(
                id: id,
                label: label,
                enabled: true,
                email: nil,
                usesAmbientAuthFile: ambient,
                grokHomePath: standardizedHome
            )
        )
        assignIdentity(incoming, fallback: fallback, to: id, accounts: &accounts)
        return id
    }

    /// Persist an identity only when no other row already uses it.
    @discardableResult
    static func assignIdentity(
        _ identity: String?,
        fallback: String?,
        to id: UUID,
        accounts: inout [GrokAccount]
    ) -> Bool {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return false }
        let preferred = CodexCLIAuth.usableEmail(identity)
            ?? AccountIdentity.usableHandle(identity)
        let unique = AccountIdentity.usableHandle(fallback)
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
            if let current = accounts[index].email,
               let preferred,
               current.caseInsensitiveCompare(preferred) != .orderedSame {
                next = current
            } else {
                next = unique
            }
        } else {
            next = accounts[index].email ?? unique
        }
        guard accounts[index].email != next else { return false }
        accounts[index].email = next
        return true
    }

    /// Snapshot from the token that fetched billing wins over a stored email.
    /// Colliding titles fall back to label, then a shortened subject / home id.
    static func cardTitles(_ cards: [CardInput]) -> [UUID: String] {
        var taken = Set<String>()
        var result: [UUID: String] = [:]
        for card in cards {
            let preferred = AccountIdentity.usableHandle(card.snapshotEmail)
                ?? AccountIdentity.usableHandle(card.storedEmail)
            var candidates: [String] = []
            if let preferred {
                candidates.append(preferred)
            }
            let label = card.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty,
               candidates.allSatisfy({ $0.caseInsensitiveCompare(label) != .orderedSame }) {
                candidates.append(label)
            }
            if let unique = AccountIdentity.usableHandle(card.uniqueFallback),
               candidates.allSatisfy({ $0.caseInsensitiveCompare(unique) != .orderedSame }) {
                candidates.append(unique)
            }
            let chosen = candidates.first { !taken.contains($0.lowercased()) }
                ?? candidates.last
                ?? "Grok"
            taken.insert(chosen.lowercased())
            result[card.id] = chosen
        }
        return result
    }
}
