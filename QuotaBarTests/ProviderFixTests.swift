import XCTest
@testable import QuotaBar

final class ProviderFixTests: XCTestCase {
    func testPercentClampBoundsFiniteValues() {
        XCTAssertEqual(Percent.clamp(140), 100)
        XCTAssertEqual(Percent.clamp(-5), 0)
        XCTAssertEqual(Percent.clamp(40), 40)
        XCTAssertEqual(Percent.clamp(.infinity), 0)
        XCTAssertEqual(Percent.clamp(.nan), 0)
        XCTAssertEqual(Percent.remaining(used: -5), 100)
        XCTAssertEqual(Percent.remaining(used: 40), 60)
        XCTAssertNil(JSONNumber.double(from: "nan"))
        XCTAssertNil(JSONNumber.double(from: "inf"))
    }

    func testGrokPeriodWithoutPercentIsNotZero() throws {
        let config: [String: Any] = [
            "currentPeriod": ["end": "2026-12-01T00:00:00Z"]
        ]
        let resetAt = TimeFormatting.parseDate("2026-12-01T00:00:00Z")
        XCTAssertNotNil(resetAt)
        let percent = try GrokClient.usedPercent(from: config, resetAt: resetAt)
        XCTAssertNil(percent)

        let snapshot = try GrokClient.parse(
            config,
            email: "g@example.com",
            planFallback: "SuperGrok"
        )
        XCTAssertNil(snapshot.session)
        XCTAssertNil(snapshot.weekly)
        XCTAssertEqual(snapshot.extraFooter, "No usage percent this billing period.")
    }

    func testGLMShallowEmailIgnoresNestedBilling() {
        let deepOnly: [String: Any] = [
            "plan": "pro",
            "billing": [
                "shared": ["email": "billing@example.com"]
            ]
        ]
        XCTAssertNil(AccountIdentity.fromShallowJSON(deepOnly))
        XCTAssertEqual(AccountIdentity.fromJSON(deepOnly), "billing@example.com")

        let shallow: [String: Any] = [
            "user": ["email": "real@example.com"],
            "billing": [
                "shared": ["email": "billing@example.com"]
            ]
        ]
        XCTAssertEqual(AccountIdentity.fromShallowJSON(shallow), "real@example.com")
    }

    func testCursorLauncherIncludesAnysphereIdentifiers() {
        XCTAssertTrue(CursorAppLauncher.bundleIdentifiers.contains("com.todesktop.230313mzl4w4u92"))
        XCTAssertTrue(CursorAppLauncher.bundleIdentifiers.contains("com.anysphere.cursor"))
    }

    func testKeychainUUIDScopedDetection() {
        XCTAssertTrue(KeychainStore.isUUIDScoped("chatgpt.cookie.AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        XCTAssertTrue(KeychainStore.isUUIDScoped("grok.oauth-token.AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        XCTAssertFalse(KeychainStore.isUUIDScoped("cursor.cookie"))
        XCTAssertFalse(KeychainStore.isUUIDScoped("glm.api-key"))
        XCTAssertFalse(KeychainStore.isUUIDScoped("chatgpt.cookie.not-a-uuid"))
    }

    func testCorruptConfigIsNotReconciledOrTreatedAsEmptyAccounts() {
        XCTAssertEqual(ConfigStore.classify(data: nil), .missing)
        XCTAssertEqual(ConfigStore.classify(data: Data()), .corrupt)
        XCTAssertEqual(ConfigStore.classify(data: Data("{".utf8)), .corrupt)
        XCTAssertEqual(ConfigStore.classify(data: Data("{}".utf8)), .decoded)
        XCTAssertFalse(ConfigStore.shouldReconcileKeychain(.missing))
        XCTAssertFalse(ConfigStore.shouldReconcileKeychain(.corrupt))
        XCTAssertTrue(ConfigStore.shouldReconcileKeychain(.decoded))
    }

    func testCodexRefreshSkipsUnmanagedHome() throws {
        let unmanaged = FileManager.default.temporaryDirectory
            .appendingPathComponent("qb-unmanaged-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: unmanaged, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: unmanaged) }
        let url = unmanaged.appendingPathComponent("auth.json")
        let original = Data(#"{"tokens":{"access_token":"old"}}"#.utf8)
        try original.write(to: url)
        try CodexCLIAuth.persistRefreshedTokens(
            home: unmanaged,
            tokens: CodexCLIAuth.Tokens(accessToken: "new-token")
        )
        XCTAssertEqual(try Data(contentsOf: url), original)

        let managed = CodexCLIAuth.makeManagedHomeURL()
        defer { try? FileManager.default.removeItem(at: managed) }
        try CodexCLIAuth.persistRefreshedTokens(
            home: managed,
            tokens: CodexCLIAuth.Tokens(accessToken: "managed-token")
        )
        XCTAssertEqual(CodexCLIAuth.read(home: managed)?.accessToken, "managed-token")
    }

    func testCodexWriteOnlyManagedHome() {
        let ambient = CodexCLIAuth.defaultHomeURL()
        XCTAssertTrue(CodexCLIAuth.isAmbientHome(ambient))
        XCTAssertFalse(CodexCLIAuth.isManagedHome(ambient))
        let managed = CodexCLIAuth.makeManagedHomeURL()
        XCTAssertTrue(CodexCLIAuth.isManagedHome(managed))
    }

    func testChatGPTFallbackDoesNotMixCookieAndCodex() {
        let cookieIdentity = ChatGPTClient.Identity(
            accessToken: "cookie-token",
            email: "cookie@example.com",
            planName: "Plus",
            accountId: "cookie-acct",
            planExpiresAt: nil
        )
        let mixed = ChatGPTClient.exclusiveFallback(
            cookieIdentity: cookieIdentity,
            cookie: "session=abc",
            codexTokens: .init(
                accessToken: "codex-token",
                refreshToken: "refresh",
                idToken: nil,
                accountId: "codex-acct",
                email: "codex@example.com"
            )
        )
        XCTAssertEqual(mixed.token, "cookie-token")
        XCTAssertEqual(mixed.email, "cookie@example.com")
        XCTAssertEqual(mixed.cookie, "session=abc")
        XCTAssertNotEqual(mixed.email, "codex@example.com")

        let codexOnly = ChatGPTClient.exclusiveFallback(
            cookieIdentity: nil,
            cookie: "session=abc",
            codexTokens: .init(accessToken: "codex-token", email: "codex@example.com")
        )
        XCTAssertEqual(codexOnly.token, "codex-token")
        XCTAssertEqual(codexOnly.email, "codex@example.com")
        XCTAssertNil(codexOnly.cookie)
    }
}
