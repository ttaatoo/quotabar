import XCTest
@testable import QuotaBar

final class RefreshCoordinatorTests: XCTestCase {
    func testOldGenerationIsNotCurrent() {
        let coordinator = RefreshCoordinator()
        let first = coordinator.begin("chatgpt")
        let second = coordinator.begin("chatgpt")
        XCTAssertTrue(coordinator.isRefreshing)
        XCTAssertFalse(coordinator.isCurrent("chatgpt", generation: first))
        XCTAssertTrue(coordinator.isCurrent("chatgpt", generation: second))
        coordinator.finish("chatgpt", generation: first)
        XCTAssertTrue(coordinator.isRefreshing)
        coordinator.finish("chatgpt", generation: second)
        XCTAssertFalse(coordinator.isRefreshing)
    }

    func testNeedsOpenRefreshSkipsFreshReady() {
        let snapshot = UsageSnapshot(
            provider: .cursor,
            planName: "Pro",
            fetchedAt: Date().addingTimeInterval(-10),
            session: UsageWindow(title: "Session", remainingPercent: 40, usedPercent: 60),
            weekly: nil,
            source: .live
        )
        XCTAssertFalse(
            RefreshCoordinator.needsOpenRefresh(.ready(snapshot), force: false)
        )
        XCTAssertTrue(
            RefreshCoordinator.needsOpenRefresh(.ready(snapshot), force: true)
        )
        XCTAssertTrue(
            RefreshCoordinator.needsOpenRefresh(.failure("nope"), force: false)
        )
        let staleSnap = snapshot
        let old = UsageSnapshot(
            provider: .cursor,
            planName: "Pro",
            fetchedAt: Date().addingTimeInterval(-45),
            session: staleSnap.session,
            weekly: nil,
            source: .live
        )
        XCTAssertTrue(
            RefreshCoordinator.needsOpenRefresh(.ready(old), force: false)
        )
    }

    func testPollBackoffIgnoresSignedOutWhenAnotherAccountSucceeds() {
        let observations: [RefreshCoordinator.PollObservation] = [
            .ignored,
            .success,
            .transportFailure
        ]
        XCTAssertEqual(RefreshCoordinator.nextPollFailureCount(current: 4, observations: observations), 0)
        XCTAssertEqual(
            RefreshCoordinator.nextPollFailureCount(current: 1, observations: [.transportFailure, .ignored]),
            2
        )
        XCTAssertEqual(
            RefreshCoordinator.nextPollFailureCount(current: 3, observations: [.ignored, .ignored]),
            0
        )
        XCTAssertEqual(
            RefreshCoordinator.observation(hasCredentials: false, state: .signedOut("sign in")),
            .ignored
        )
        XCTAssertEqual(
            RefreshCoordinator.observation(hasCredentials: true, state: .stale(snapshot(), message: "Timed out after 30s.")),
            .transportFailure
        )
        XCTAssertEqual(
            RefreshCoordinator.observation(hasCredentials: true, state: .failure("session expired")),
            .ignored
        )
        XCTAssertFalse(
            RefreshCoordinator.showsSyntheticSignedOutCard(savedAccountCount: 2, visibleAccountCount: 0)
        )
        XCTAssertTrue(
            RefreshCoordinator.showsSyntheticSignedOutCard(savedAccountCount: 0, visibleAccountCount: 0)
        )
    }

    private func snapshot() -> UsageSnapshot {
        UsageSnapshot(
            provider: .chatgpt,
            planName: "Plus",
            fetchedAt: Date(),
            session: nil,
            weekly: UsageWindow(title: "Weekly", remainingPercent: 40, usedPercent: 60),
            source: .live
        )
    }

    func testBackoffGrowsThenCaps() {
        XCTAssertEqual(RefreshCoordinator.pollDelay(base: 120, consecutiveFailures: 0), 120)
        XCTAssertEqual(RefreshCoordinator.pollDelay(base: 120, consecutiveFailures: 1), 240)
        XCTAssertEqual(RefreshCoordinator.pollDelay(base: 120, consecutiveFailures: 5), 30 * 60)
        XCTAssertEqual(RefreshCoordinator.pollDelay(base: 120, consecutiveFailures: 8), 30 * 60)
    }

    func testNextScheduledAtSkipsMissedTicks() {
        let previous = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 1_000 + 350)
        let next = RefreshCoordinator.nextScheduledAt(previous: previous, interval: 120, now: now)
        XCTAssertGreaterThan(next, now)
        XCTAssertEqual(next.timeIntervalSince1970, 1_000 + 360, accuracy: 0.01)
    }
}
