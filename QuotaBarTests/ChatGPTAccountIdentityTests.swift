import XCTest
@testable import QuotaBar

final class ChatGPTAccountIdentityTests: XCTestCase {
    func testIdentitiesMatchRequiresBothEmails() {
        XCTAssertFalse(ChatGPTAccountIdentity.identitiesMatch(nil, "a@example.com"))
        XCTAssertTrue(ChatGPTAccountIdentity.identitiesMatch(nil, nil))
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

    func testExpiredChatGPTMessageIsRelogin() {
        XCTAssertEqual(
            ChatGPTAccountIdentity.Recovery.action(
                for: .failure("This account's Codex login expired. Re-login this account in Settings.")
            ),
            .relogin
        )
    }
}
