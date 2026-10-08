import XCTest
@testable import QuotaBar

final class FailureStateTests: XCTestCase {
    private func snapshot() -> UsageSnapshot {
        UsageSnapshot(
            provider: .chatgpt,
            planName: "Plus",
            fetchedAt: Date(),
            session: nil,
            weekly: UsageWindow(title: "Weekly", remainingPercent: 40, usedPercent: 60),
            source: .live,
            extraFooter: nil
        )
    }

    func testAuthFailureWithCredentialsBecomesFailure() {
        let previous = ProviderLoadState.ready(snapshot())
        let next = ProviderLoadState.afterFailure(
            previous: previous,
            error: QuotaError.unauthorized("session expired"),
            hasCredentials: true,
            signInHint: "sign in"
        )
        XCTAssertEqual(next, .failure("session expired"))
        XCTAssertNil(next.staleMessage)
    }

    func testNetworkFailurePreservesSnapshotAsStale() {
        let previous = ProviderLoadState.ready(snapshot())
        let next = ProviderLoadState.afterFailure(
            previous: previous,
            error: QuotaError.network("Timed out after 30s."),
            hasCredentials: true,
            signInHint: "sign in"
        )
        if case .stale(let snap, let message) = next {
            XCTAssertEqual(snap.planName, "Plus")
            XCTAssertEqual(message, "Timed out after 30s.")
        } else {
            XCTFail("expected stale, got \(next)")
        }
    }

    func testAuthWithoutCredentialsIsSignedOut() {
        let next = ProviderLoadState.afterFailure(
            previous: .idle,
            error: QuotaError.notSignedIn("no cookie"),
            hasCredentials: false,
            signInHint: "sign in"
        )
        XCTAssertEqual(next, .signedOut("no cookie"))
    }

    func testCancellationKeepsPreviousState() {
        let previous = ProviderLoadState.ready(snapshot())
        let next = ProviderLoadState.afterFailure(
            previous: previous,
            error: QuotaError.cancelled,
            hasCredentials: true,
            signInHint: "sign in"
        )
        XCTAssertEqual(next, previous)
        XCTAssertFalse(QuotaError.cancelled.shouldPreservePriorSnapshot)
        let wrapped = RefreshWork.quotaError(URLError(.cancelled))
        XCTAssertEqual(wrapped, .cancelled)
        XCTAssertTrue(wrapped.isCancellation)
        let described = RefreshWork.quotaError(URLError(.cancelled))
        XCTAssertNotEqual(described, .network("cancelled"))
    }

    func testHTTP429DoesNotPreserveReady() {
        let next = ProviderLoadState.afterFailure(
            previous: .ready(snapshot()),
            error: QuotaError.http(429, "slow"),
            hasCredentials: true,
            signInHint: "sign in"
        )
        XCTAssertEqual(next, .failure("HTTP 429: slow"))
    }

    func testExpiredStaleCardOffersRelogin() {
        let stale = ProviderLoadState.stale(snapshot(), message: GrokAuth.expiredTokenMessage)
        XCTAssertEqual(GrokAccountIdentity.Recovery.action(for: stale), .relogin)
        XCTAssertTrue(stale.showsUserInitiatedLoading)
    }

    func testChatGPTExpiredFailureOffersRelogin() {
        let failure = ProviderLoadState.failure("chatgpt.com rejected the session cookie.")
        XCTAssertEqual(ChatGPTAccountIdentity.Recovery.action(for: failure), .relogin)
        XCTAssertTrue(failure.showsUserInitiatedLoading)
        XCTAssertTrue(AccountCardRow(
            id: "x",
            email: "a@b.com",
            fallbackTitle: "ChatGPT",
            state: failure,
            hasCredentials: true,
            recoveryTitle: ChatGPTAccountIdentity.Recovery.action(for: failure).buttonTitle
        ).showsRecoveryAction)
    }

    func testFetchAttemptMarksPreservedStale() {
        let attempt = FetchAttempt(
            id: "chatgpt:a",
            provider: .chatgpt,
            accountLabel: "a@example.com",
            finishedAt: Date(),
            kind: "stale",
            message: "Timed out after 30s.",
            durationMs: 1200,
            preservedStale: true
        )
        XCTAssertTrue(attempt.summary.contains("kept meters"))
        XCTAssertTrue(attempt.summary.contains("ChatGPT"))
    }

    func testNetworkFailureKeepsRetry() {
        let stale = ProviderLoadState.stale(snapshot(), message: "Timed out after 30s.")
        XCTAssertEqual(ChatGPTAccountIdentity.Recovery.action(for: stale), .retryRefresh)
        XCTAssertEqual(GrokAccountIdentity.Recovery.action(for: stale), .retryRefresh)
    }
}
