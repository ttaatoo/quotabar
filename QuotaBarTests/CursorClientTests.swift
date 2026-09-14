import XCTest
@testable import QuotaBar

final class CursorClientTests: XCTestCase {
    func testVercelHTML403IsCheckpointNotUnauthorized() {
        let html = Data(
            """
            <!DOCTYPE html>
            <html><head><title>Vercel Security Checkpoint</title></head>
            <body>Vercel Security Checkpoint</body></html>
            """.utf8
        )
        XCTAssertEqual(
            CursorHTTP.classify(status: 403, data: html, contentType: "text/html; charset=utf-8"),
            .checkpoint
        )
        XCTAssertTrue(CursorHTTP.isCheckpoint(status: 403, data: html, contentType: "text/html"))
        XCTAssertFalse(CursorHTTP.isUnauthenticated(status: 403, data: html, contentType: "text/html"))
        XCTAssertFalse(CursorAuth.isRejectedSessionMessage(CursorHTTP.checkpointMessage))
    }

    func testJSON401AndNotAuthenticatedAreUnauthorized() {
        let body = Data(#"{"error":"not_authenticated"}"#.utf8)
        XCTAssertEqual(
            CursorHTTP.classify(status: 401, data: body, contentType: "application/json"),
            .unauthorized
        )
        XCTAssertEqual(
            CursorHTTP.classify(status: 200, data: body, contentType: "application/json"),
            .unauthorized
        )
        XCTAssertEqual(
            CursorHTTP.classify(
                status: 403,
                data: Data(#"{"code":"unauthenticated"}"#.utf8),
                contentType: "application/json"
            ),
            .unauthorized
        )
    }

    func testRefreshRunsOnlyOnAmbientUnauthorized() {
        let auth = QuotaError.unauthorized(CursorAuth.unauthenticatedMessage)
        let checkpoint = QuotaError.network(CursorHTTP.checkpointMessage)
        let wafHTTP = QuotaError.http(403, "Vercel Security Checkpoint")

        XCTAssertTrue(CursorClient.shouldAttemptRefresh(kind: .ambient, error: auth))
        XCTAssertFalse(CursorClient.shouldAttemptRefresh(kind: .pasted, error: auth))
        XCTAssertFalse(CursorClient.shouldAttemptRefresh(kind: .ambient, error: checkpoint))
        XCTAssertFalse(CursorClient.shouldAttemptRefresh(kind: .ambient, error: wafHTTP))
        XCTAssertFalse(wafHTTP.isAuthFailure)
        XCTAssertTrue(auth.isAuthFailure)
    }

    func testParseAPI2PlanUsageMapsPercentsAndCycleEnd() throws {
        let raw: [String: Any] = [
            "billingCycleStart": "1768399334000",
            "billingCycleEnd": "1771077734000",
            "planUsage": [
                "totalSpend": 23222,
                "includedSpend": 23222,
                "bonusSpend": 0,
                "remaining": 16778,
                "limit": 40000,
                "autoPercentUsed": 7.2,
                "apiPercentUsed": 12.0,
                "totalPercentUsed": 15.48
            ],
            "spendLimitUsage": [
                "individualLimit": 10000,
                "individualUsed": 245,
                "limitType": "user"
            ]
        ]
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let snapshot = try CursorClient.parsePeriodUsage(
            raw,
            fetchedAt: now,
            email: "user@example.com",
            planName: "ultra"
        )
        XCTAssertEqual(snapshot.planName, "Ultra")
        XCTAssertEqual(snapshot.accountEmail, "user@example.com")
        XCTAssertEqual(snapshot.session?.title, "Cursor Models")
        XCTAssertEqual(snapshot.session?.usedPercent ?? -1, 7.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.session?.remainingPercent ?? -1, 92.8, accuracy: 0.001)
        XCTAssertEqual(snapshot.weekly?.title, "Other Models")
        XCTAssertEqual(snapshot.weekly?.usedPercent ?? -1, 12.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.weekly?.remainingPercent ?? -1, 88.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.session?.resetAt, Date(timeIntervalSince1970: 1_771_077_734))
        XCTAssertEqual(snapshot.extraFooter, "On-demand $2.45")
    }

    func testParseAPI2SpendLimitFallback() throws {
        let raw: [String: Any] = [
            "billingCycleEnd": "1771077734000",
            "planUsage": [
                "includedSpend": 2000,
                "limit": 40000,
                "totalPercentUsed": 5.0
            ]
        ]
        let snapshot = try CursorClient.parsePeriodUsage(raw, fetchedAt: Date(), planName: "pro")
        XCTAssertEqual(snapshot.planName, "Pro")
        XCTAssertEqual(snapshot.session?.usedPercent ?? -1, 5.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.session?.remainingPercent ?? -1, 95.0, accuracy: 0.001)
        XCTAssertNil(snapshot.weekly)
    }

    func testBearerTokenIsRawJWTNotCookie() {
        let jwt = "aaa.bbb.ccc"
        let cookie = "WorkosCursorSessionToken=user_abc%3A%3A\(jwt)"
        XCTAssertEqual(CursorAuth.bearerAccessToken(fromCookie: cookie), jwt)
        XCTAssertEqual(CursorAuth.bearerAccessToken(fromStored: cookie), jwt)
        XCTAssertEqual(CursorAuth.bearerAccessToken(fromStored: jwt), jwt)
    }

    func testParsePeriodUsageRejectsUnauthenticatedJSON() {
        XCTAssertThrowsError(
            try CursorClient.parsePeriodUsage(["error": "not_authenticated"])
        ) { error in
            XCTAssertTrue((error as? QuotaError)?.isAuthFailure == true)
        }
    }
}
