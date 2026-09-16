import XCTest
@testable import QuotaBar

final class GrokAccountTests: XCTestCase {
    private var scratch: URL!

    override func setUp() {
        super.setUp()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotabar-grok-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: scratch)
        scratch = nil
        super.tearDown()
    }

    func testTwoManagedHomesWithDifferentTokensDoNotShareDisplayedEmail() throws {
        let homeA = scratch.appendingPathComponent("home-a", isDirectory: true)
        let homeB = scratch.appendingPathComponent("home-b", isDirectory: true)
        let tokenA = jwt(sub: "user-aaa-111", email: "alpha@example.com")
        let tokenB = jwt(sub: "user-bbb-222", email: "beta@example.com")
        try writeAuth(home: homeA, token: tokenA, email: "alpha@example.com", userId: "aaa")
        try writeAuth(home: homeB, token: tokenB, email: "alpha@example.com", userId: "aaa")

        let credsA = try XCTUnwrap(GrokAuth.loadAuthFile(home: homeA))
        let credsB = try XCTUnwrap(GrokAuth.loadAuthFile(home: homeB))
        XCTAssertNotEqual(credsA.accessToken, credsB.accessToken)

        let decoy = "alpha@example.com"
        let resolvedA = GrokAccountIdentity.resolve(credentials: credsA, settingsEmail: decoy)
        let resolvedB = GrokAccountIdentity.resolve(credentials: credsB, settingsEmail: decoy)
        XCTAssertEqual(resolvedA.display, "alpha@example.com")
        XCTAssertEqual(resolvedB.display, "beta@example.com")
        XCTAssertNotEqual(resolvedA.cardIdentity, resolvedB.cardIdentity)

        let idA = UUID()
        let idB = UUID()
        let titles = GrokAccountIdentity.cardTitles([
            .init(
                id: idA,
                storedEmail: "alpha@example.com",
                snapshotEmail: resolvedA.cardIdentity,
                label: "Grok",
                uniqueFallback: resolvedA.uniqueFallback
            ),
            .init(
                id: idB,
                storedEmail: "alpha@example.com",
                snapshotEmail: resolvedB.cardIdentity,
                label: "Grok 2",
                uniqueFallback: resolvedB.uniqueFallback
            )
        ])
        XCTAssertEqual(titles[idA], "alpha@example.com")
        XCTAssertEqual(titles[idB], "beta@example.com")
    }

    func testStaleAuthEmailDoesNotHideTokenSubjectWhenSettingsCollides() throws {
        let tokenA = jwt(sub: "subject-one-aaaa")
        let tokenB = jwt(sub: "subject-two-bbbb")
        let credsA = GrokAuth.Credentials(
            accessToken: tokenA,
            email: "shared@example.com",
            userId: "stale-user",
            expiresAt: nil,
            authMode: "oidc",
            teamId: nil,
            oidcScope: nil,
            source: .authFile
        )
        let credsB = GrokAuth.Credentials(
            accessToken: tokenB,
            email: "shared@example.com",
            userId: "stale-user",
            expiresAt: nil,
            authMode: "oidc",
            teamId: nil,
            oidcScope: nil,
            source: .authFile
        )
        let resolvedA = GrokAccountIdentity.resolve(credentials: credsA, settingsEmail: "shared@example.com")
        let resolvedB = GrokAccountIdentity.resolve(credentials: credsB, settingsEmail: "shared@example.com")
        XCTAssertEqual(resolvedA.display, "shared@example.com")
        XCTAssertEqual(resolvedB.display, "shared@example.com")
        XCTAssertNotEqual(resolvedA.uniqueFallback, resolvedB.uniqueFallback)

        let idA = UUID()
        let idB = UUID()
        let titles = GrokAccountIdentity.cardTitles([
            .init(
                id: idA,
                storedEmail: "shared@example.com",
                snapshotEmail: resolvedA.display,
                label: "Grok",
                uniqueFallback: resolvedA.uniqueFallback
            ),
            .init(
                id: idB,
                storedEmail: "shared@example.com",
                snapshotEmail: resolvedB.display,
                label: "Grok 2",
                uniqueFallback: resolvedB.uniqueFallback
            )
        ])
        XCTAssertEqual(titles[idA], "shared@example.com")
        XCTAssertEqual(titles[idB], "Grok 2")
        XCTAssertNotEqual(titles[idA], titles[idB])
    }

    func testCardTitlePrefersSnapshotEmailOverStaleStoredEmail() {
        let id = UUID()
        let titles = GrokAccountIdentity.cardTitles([
            .init(
                id: id,
                storedEmail: "stale@example.com",
                snapshotEmail: "live@example.com",
                label: "Grok",
                uniqueFallback: "subj-1"
            )
        ])
        XCTAssertEqual(titles[id], "live@example.com")
    }

    func testUpsertDoesNotRewireAnotherAccountHomeBecauseEmailCollided() throws {
        let homeA = scratch.appendingPathComponent("acct-a", isDirectory: true)
        let homeB = scratch.appendingPathComponent("acct-b", isDirectory: true)
        let tokenA = jwt(sub: "token-a", email: "one@example.com")
        let tokenB = jwt(sub: "token-b", email: "two@example.com")
        try writeAuth(home: homeA, token: tokenA, email: "shared@example.com", userId: "ua")
        try writeAuth(home: homeB, token: tokenB, email: "shared@example.com", userId: "ub")

        let pathA = homeA.path(percentEncoded: false)
        let pathB = homeB.path(percentEncoded: false)
        var accounts = [
            GrokAccount(
                id: UUID(),
                label: "Grok",
                email: "shared@example.com",
                grokHomePath: pathA
            )
        ]
        let firstID = accounts[0].id

        let secondID = GrokAccountIdentity.upsertFromHome(
            accounts: &accounts,
            homePath: pathB,
            email: "shared@example.com",
            ambient: false,
            accessToken: tokenB,
            userId: "ub",
            nextLabel: "Grok 2"
        )

        XCTAssertEqual(accounts.count, 2)
        XCTAssertNotEqual(secondID, firstID)
        XCTAssertTrue(GrokAuth.homesMatch(accounts.first { $0.id == firstID }?.grokHomePath, pathA))
        XCTAssertTrue(GrokAuth.homesMatch(accounts.first { $0.id == secondID }?.grokHomePath, pathB))
        XCTAssertNotEqual(
            accounts.first { $0.id == firstID }?.email,
            accounts.first { $0.id == secondID }?.email
        )
    }

    func testUpsertSameHomeDoesNotCreateASecondRow() throws {
        let home = scratch.appendingPathComponent("same-home", isDirectory: true)
        let token = jwt(sub: "same-session", email: "same@example.com")
        try writeAuth(home: home, token: token, email: "same@example.com", userId: "u")
        let path = home.path(percentEncoded: false)
        var accounts: [GrokAccount] = []

        let first = GrokAccountIdentity.upsertFromHome(
            accounts: &accounts,
            homePath: path,
            email: "same@example.com",
            ambient: false,
            accessToken: token,
            userId: "u",
            nextLabel: "Grok"
        )
        let second = GrokAccountIdentity.upsertFromHome(
            accounts: &accounts,
            homePath: path,
            email: "same@example.com",
            ambient: false,
            accessToken: token,
            userId: "u",
            nextLabel: "Grok 2"
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(accounts.count, 1)
        XCTAssertTrue(GrokAuth.homesMatch(accounts[0].grokHomePath, path))
    }

    func testAssignIdentityRefusesToCopyAnotherAccountsEmail() {
        let idA = UUID()
        let idB = UUID()
        var accounts = [
            GrokAccount(id: idA, label: "Grok", email: "owner@example.com", grokHomePath: "/tmp/a"),
            GrokAccount(id: idB, label: "Grok 2", email: nil, grokHomePath: "/tmp/b")
        ]
        GrokAccountIdentity.assignIdentity(
            "owner@example.com",
            fallback: "subj-b",
            to: idB,
            accounts: &accounts
        )
        XCTAssertEqual(accounts.first { $0.id == idA }?.email, "owner@example.com")
        XCTAssertEqual(accounts.first { $0.id == idB }?.email, "subj-b")
        XCTAssertEqual(accounts.first { $0.id == idA }?.grokHomePath, "/tmp/a")
    }

    func testSettingsTreeWalkNoLongerStealsANestedDecoyEmail() {
        let payload: [String: Any] = [
            "subscription_tier_display": "SuperGrok",
            "billing": [
                "contact": [
                    "email": "billing-shared@x.ai"
                ]
            ]
        ]
        XCTAssertEqual(AccountIdentity.fromJSON(payload), "billing-shared@x.ai")
        XCTAssertNil(GrokAccountIdentity.emailFromUserObject(payload))
    }

    func testParseDoesNotTakeANestedBillingEmail() throws {
        let raw: [String: Any] = [
            "config": [
                "creditUsagePercent": 9,
                "currentPeriod": ["end": "2026-10-01T00:00:00Z"]
            ],
            "org": [
                "email": "org-shared@x.ai"
            ]
        ]
        let snapshot = try GrokClient.parse(raw, email: nil, planFallback: "SuperGrok")
        XCTAssertNil(snapshot.accountEmail)
        XCTAssertEqual(snapshot.weekly?.remainingPercent ?? -1, 91, accuracy: 0.001)
    }

    func testParseKeepsCallerEmailBoundToTheToken() throws {
        let raw: [String: Any] = [
            "config": [
                "creditUsagePercent": 64,
                "currentPeriod": ["end": "2026-10-01T00:00:00Z"]
            ],
            "email": "top-level@example.com"
        ]
        let snapshot = try GrokClient.parse(
            raw,
            email: "from-token@example.com",
            planFallback: "SuperGrok"
        )
        XCTAssertEqual(snapshot.accountEmail, "from-token@example.com")
    }

    func testMatchExistingIgnoresEmailAndRequiresHomeOrToken() throws {
        let homeA = scratch.appendingPathComponent("match-a", isDirectory: true)
        let homeB = scratch.appendingPathComponent("match-b", isDirectory: true)
        let tokenA = jwt(sub: "match-a")
        let tokenB = jwt(sub: "match-b")
        try writeAuth(home: homeA, token: tokenA, email: "same@example.com")
        try writeAuth(home: homeB, token: tokenB, email: "same@example.com")

        let accountA = GrokAccount(
            id: UUID(),
            label: "Grok",
            email: "same@example.com",
            grokHomePath: homeA.path(percentEncoded: false)
        )
        XCTAssertNil(
            GrokAccountIdentity.matchExisting(
                accounts: [accountA],
                homePath: homeB.path(percentEncoded: false),
                accessToken: tokenB
            )
        )
        XCTAssertEqual(
            GrokAccountIdentity.matchExisting(
                accounts: [accountA],
                homePath: homeA.path(percentEncoded: false),
                accessToken: tokenB
            )?.id,
            accountA.id
        )
    }

    private func jwt(sub: String, email: String? = nil, name: String? = nil) -> String {
        func encode(_ object: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        var payload: [String: Any] = ["sub": sub]
        if let email {
            payload["email"] = email
        }
        if let name {
            payload["name"] = name
        }
        return "\(encode(["alg": "none", "typ": "JWT"])).\(encode(payload)).sig"
    }

    private func writeAuth(home: URL, token: String, email: String?, userId: String? = nil) throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var entry: [String: Any] = [
            "key": token,
            "auth_mode": "oidc"
        ]
        if let email {
            entry["email"] = email
        }
        if let userId {
            entry["user_id"] = userId
        }
        let root = ["https://auth.x.ai::quota-test": entry]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        try data.write(to: home.appendingPathComponent("auth.json"), options: .atomic)
    }
}
