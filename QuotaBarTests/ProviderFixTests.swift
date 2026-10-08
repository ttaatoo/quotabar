import XCTest
@testable import QuotaBar

final class ProviderFixTests: XCTestCase {
    func testPercentClampBoundsFiniteValues() {
        XCTAssertEqual(Percent.clamp(140), 100)
        XCTAssertEqual(Percent.clamp(-5), 0)
        XCTAssertEqual(Percent.clamp(40), 40)
        XCTAssertEqual(Percent.clamp(.infinity), 0)
        XCTAssertEqual(Percent.clamp(.nan), 0)
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
                email: "codex@example.com",
                accountId: "codex-acct"
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
