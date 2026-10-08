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

    func testAuthFailureLeavesReadyEvenWithCredentials() {
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
            error: QuotaError.network("Cancelled."),
            hasCredentials: true,
            signInHint: "sign in"
        )
        XCTAssertEqual(next, previous)
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
}
