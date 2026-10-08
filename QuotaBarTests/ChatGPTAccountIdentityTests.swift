import XCTest
@testable import QuotaBar

final class ChatGPTAccountIdentityTests: XCTestCase {
    func testIdentitiesMatchRequiresBothEmails() {
        XCTAssertFalse(ChatGPTAccountIdentity.identitiesMatch(nil, "a@example.com"))
        XCTAssertFalse(ChatGPTAccountIdentity.identitiesMatch(nil, nil))
        XCTAssertFalse(ChatGPTAccountIdentity.identitiesMatch("a@example.com", "b@example.com"))
        XCTAssertTrue(ChatGPTAccountIdentity.identitiesMatch("a@example.com", "A@example.com"))
        XCTAssertTrue(ChatGPTAccountIdentity.emailsCompatible(nil, "a@example.com"))
        XCTAssertFalse(ChatGPTAccountIdentity.emailsCompatible("a@example.com", "b@example.com"))
    }

    func testTwoHomesWithSameEmailStayTwoAccounts() {
        var accounts: [ChatGPTAccount] = []
        let idA = ChatGPTAccountIdentity.upsertFromHome(
            accounts: &accounts,
            homePath: "/tmp/codex-a",
            email: "same@example.com",
            ambient: false,
            accessToken: "tok-a",
            nextLabel: "ChatGPT"
        )
        let idB = ChatGPTAccountIdentity.upsertFromHome(
            accounts: &accounts,
            homePath: "/tmp/codex-b",
            email: "same@example.com",
            ambient: false,
            accessToken: "tok-b",
            nextLabel: "ChatGPT 2"
        )
        XCTAssertEqual(accounts.count, 2)
        XCTAssertNotEqual(idA, idB)
        XCTAssertEqual(accounts.filter { $0.email == "same@example.com" }.count, 1)
        XCTAssertTrue(accounts.contains { $0.id == idB && $0.email == nil })
    }

    func testSameHomeDoesNotCreateSecondRow() {
        var accounts: [ChatGPTAccount] = []
        let first = ChatGPTAccountIdentity.upsertFromHome(
            accounts: &accounts,
            homePath: "/tmp/codex-shared",
            email: "one@example.com",
            ambient: false,
            accessToken: "tok",
            nextLabel: "ChatGPT"
        )
        let second = ChatGPTAccountIdentity.upsertFromHome(
            accounts: &accounts,
            homePath: "/tmp/codex-shared",
            email: "one@example.com",
            ambient: false,
            accessToken: "tok",
            nextLabel: "ChatGPT 2"
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(accounts.count, 1)
    }

    func testCookieWithoutEmailDoesNotMatchNamedAccount() {
        XCTAssertFalse(ChatGPTAccountIdentity.identitiesMatch(nil, "saved@example.com"))
        XCTAssertNil(
            ChatGPTAccountIdentity.matchExisting(
                accounts: [
                    ChatGPTAccount(id: UUID(), label: "ChatGPT", email: "saved@example.com")
                ],
                homePath: nil,
                accessToken: nil
            )
        )
    }

    func testVisibleAccountsDoNotFallbackWhenAllDisabled() {
        var settings = AppSettings.default
        settings.chatgptAccounts = [
            ChatGPTAccount(id: UUID(), label: "A", enabled: false, email: "a@example.com"),
            ChatGPTAccount(id: UUID(), label: "B", enabled: false, email: "b@example.com")
        ]
        XCTAssertTrue(settings.visibleChatGPTAccounts.isEmpty)
        settings.grokAccounts = [
            GrokAccount(id: UUID(), label: "G", enabled: false)
        ]
        XCTAssertTrue(settings.visibleGrokAccounts.isEmpty)
        settings.opencodeGoAccounts = [
            OpenCodeGoAccount(id: UUID(), label: "O", enabled: false)
        ]
        XCTAssertTrue(settings.visibleOpenCodeGoAccounts.isEmpty)
    }

    func testSameAccessTokenOnDiskDoesNotDeleteTheOtherHome() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotabar-chatgpt-token-\(UUID().uuidString)", isDirectory: true)
        let homeA = root.appendingPathComponent("a", isDirectory: true)
        let homeB = root.appendingPathComponent("b", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeCodexAuth(home: homeA, token: "shared-access-token")
        try writeCodexAuth(home: homeB, token: "shared-access-token")

        let idA = UUID()
        var accounts = [
            ChatGPTAccount(
                id: idA,
                label: "A",
                codexHomePath: homeA.path(percentEncoded: false)
            )
        ]
        let matched = ChatGPTAccountIdentity.matchExisting(
            accounts: accounts,
            homePath: homeB.path(percentEncoded: false),
            accessToken: "shared-access-token"
        )
        XCTAssertEqual(matched?.id, idA)

        let kept = ChatGPTAccountIdentity.upsertFromHome(
            accounts: &accounts,
            homePath: homeB.path(percentEncoded: false),
            email: "same@example.com",
            ambient: false,
            accessToken: "shared-access-token",
            nextLabel: "ChatGPT 2"
        )
        XCTAssertEqual(kept, idA)
        XCTAssertEqual(accounts.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: homeA.appendingPathComponent("auth.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: homeB.appendingPathComponent("auth.json").path))
    }

    func testReloginHintAloneIsNotAnExpiredSession() {
        XCTAssertEqual(
            ChatGPTAccountIdentity.Recovery.action(
                for: .failure("Couldn't refresh. Re-login this account in Settings.")
            ),
            .retryRefresh
        )
    }

    private func writeCodexAuth(home: URL, token: String) throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let object: [String: Any] = [
            "tokens": [
                "access_token": token,
                "refresh_token": "refresh-\(token)"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: home.appendingPathComponent("auth.json"))
    }

    func testExpiredChatGPTMessageIsRelogin() {
        XCTAssertEqual(
            ChatGPTAccountIdentity.Recovery.action(
                for: .failure("This account's Codex login expired. Re-login this account in Settings.")
            ),
            .relogin
        )
    }
}
